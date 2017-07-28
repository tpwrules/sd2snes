/* sd2snes - SD card based universal cartridge for the SNES
   Copyright (C) 2009-2010 Maximilian Rehkopf <otakon@gmx.net>
   AVR firmware portion

   Inspired by and based on code from sd2iec, written by Ingo Korb et al.
   See sdcard.c|h, config.h.

   FAT file system access based on code by ChaN, Jim Brain, Ingo Korb,
   see ff.c|h.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2 of the License only.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

   usbinterface.c: usb packet interface handler
*/

#include <arm/NXP/LPC17xx/LPC17xx.h>
#include <string.h>
#include <libgen.h>
#include "bits.h"
#include "config.h"
#include "uart.h"
#include "snes.h"
#include "memory.h"
#include "fileops.h"
#include "ff.h"
#include "led.h"
#include "smc.h"
#include "timer.h"
#include "cli.h"
#include "fpga.h"
#include "fpga_spi.h"
#include "usbinterface.h"
#include "rtc.h"
#include "cfg.h"
#include "cdcuser.h"
#include "usb1.h"
#include "cheat.h"

#define MAX_STRING_LENGTH 255

#define min(a,b) \
 ({ __typeof__ (a) _a = (a); \
 __typeof__ (b) _b = (b); \
 _a < _b ? _a : _b; })
 
#define GENERATE_ENUM(ENUM) ENUM,
#define GENERATE_STRING(STRING) #STRING,

#define PRINT_FUNCTION() printf("%-20s ", __FUNCTION__);
#define PRINT_CMD(buf) printf("header=%c%c%c%c op=%s space=%s flags=%d ", buf[0], buf[1], buf[2], buf[3]          \
                                                                        , usbint_server_opcode_s[buf[4]]          \
                                                                        , usbint_server_space_s[buf[5]]           \
                                                                        , buf[6]                                  \
                                                               );
#define PRINT_DAT(num, total) printf("%d/%d ", num, total);
#define PRINT_MSG(msg) printf("%-5s ", msg);
#define PRINT_END() uart_putc('\n');
#define PRINT_STATE(state) printf("state=%-32s ", usbint_server_state_s[state]);
 
// Operations are composed of a request->response packet interface.
// Each packet it composed of Nx512B flits where N is 1 or more.
// Flits are composed of 8x64B Phits.
//
// Example USBINT_OP_GET opcode.  Note that 
// client SEND CMD[USBINT_OP_GET]
// server RECV CMD[USBINT_OP_GET]
// server SEND RSP[USBINT_OP_GET]
// server SEND DAT[USBINT_OP_GET] [repeat]
// client RECV RSP[USBINT_OP_GET]
// client RECV DAT[USBINT_OP_GET] [repeat]
//
// NOTE: it may be beneficial to support command interleaving to reduce
// latency for push-style update operations from sd2snes

#define FOREACH_SERVER_STATE(OP)            \
  OP(USBINT_SERVER_STATE_IDLE)              \
                                            \
  OP(USBINT_SERVER_STATE_HANDLE_CMD)        \
  OP(USBINT_SERVER_STATE_HANDLE_DAT)        \
  OP(USBINT_SERVER_STATE_HANDLE_DATPUSH)    \
                                            \
  OP(USBINT_SERVER_STATE_HANDLE_REQDAT)     \
  OP(USBINT_SERVER_STATE_HANDLE_EXE)        \
                                            \
  OP(USBINT_SERVER_STATE_HANDLE_LOCK)       
enum usbint_server_state_e { FOREACH_SERVER_STATE(GENERATE_ENUM) };
static const char *usbint_server_state_s[] = { FOREACH_SERVER_STATE(GENERATE_STRING) };

#define FOREACH_CLIENT_STATE(OP)                \
  OP(USBINT_CLIENT_STATE_IDLE)                  \
                                                \
  OP(USBINT_CLIENT_STATE_HANDLE_CMD)            \
  OP(USBINT_CLIENT_STATE_HANDLE_DAT)
enum usbint_client_state_e { FOREACH_CLIENT_STATE(GENERATE_ENUM) };
//static const char *usbint_client_state_s[] = { FOREACH_CLIENT_STATE(GENERATE_STRING) };

#define FOREACH_SERVER_OPCODE(OP)               \
  OP(USBINT_SERVER_OPCODE_GET)                  \
  OP(USBINT_SERVER_OPCODE_PUT)                  \
  OP(USBINT_SERVER_OPCODE_EXECUTE)              \
  OP(USBINT_SERVER_OPCODE_ATOMIC)               \
                                                \
  OP(USBINT_SERVER_OPCODE_LS)                   \
  OP(USBINT_SERVER_OPCODE_MKDIR)                \
  OP(USBINT_SERVER_OPCODE_RM)                   \
  OP(USBINT_SERVER_OPCODE_MV)                   \
                                                \
  OP(USBINT_SERVER_OPCODE_RESET)                \
  OP(USBINT_SERVER_OPCODE_BOOT)                 \
  OP(USBINT_SERVER_OPCODE_MENU_LOCK)            \
  OP(USBINT_SERVER_OPCODE_MENU_UNLOCK)          \
  OP(USBINT_SERVER_OPCODE_MENU_RESET)           \
  OP(USBINT_SERVER_OPCODE_EXE)                  \
  OP(USBINT_SERVER_OPCODE_TIME)                 \
                                                \
  OP(USBINT_SERVER_OPCODE_RESPONSE)                  
enum usbint_server_opcode_e { FOREACH_SERVER_OPCODE(GENERATE_ENUM) };
static const char *usbint_server_opcode_s[] = { FOREACH_SERVER_OPCODE(GENERATE_STRING) };

#define FOREACH_SERVER_SPACE(OP)                \
  OP(USBINT_SERVER_SPACE_FILE)                  \
  OP(USBINT_SERVER_SPACE_SNES)
enum usbint_server_space_e { FOREACH_SERVER_SPACE(GENERATE_ENUM) };
static const char *usbint_server_space_s[] = { FOREACH_SERVER_SPACE(GENERATE_STRING) };

#define FOREACH_SERVER_FLAGS(OP)               \
  OP(USBINT_SERVER_FLAGS_NONE)                 \
  OP(USBINT_SERVER_FLAGS_SKIPRESET)            \
  OP(USBINT_SERVER_FLAGS_ONLYRESET)            \
  OP(USBINT_SERVER_FLAGS_3)                    \
  OP(USBINT_SERVER_FLAGS_CLRX)                 \
  OP(USBINT_SERVER_FLAGS_5)                    \
  OP(USBINT_SERVER_FLAGS_6)                    \
  OP(USBINT_SERVER_FLAGS_7)                    \
  OP(USBINT_SERVER_FLAGS_SETX)                 
enum usbint_server_flags_e { FOREACH_SERVER_FLAGS(GENERATE_ENUM) };
//static const char *usbint_server_flags_s[] = { FOREACH_SERVER_FLAGS(GENERATE_STRING) };

volatile enum usbint_server_state_e server_state = USBINT_SERVER_STATE_IDLE;
static int reset_state = 0;

struct usbint_server_info_t {
  enum usbint_server_opcode_e opcode;
  enum usbint_server_space_e space;
  enum usbint_server_flags_e flags;
  
  uint32_t size;
  uint32_t offset;
  int error;
};

volatile struct usbint_server_info_t server_info;
extern snes_romprops_t romprops;

unsigned recv_buffer_offset = 0;
unsigned char recv_buffer[USB_BLOCK_SIZE];

// double buffered because send only guarantees that a transfer is
// volatile since CDC needs to send it
volatile uint8_t send_buffer_index = 0;
volatile unsigned char send_buffer[2][USB_DATABLOCK_SIZE];

// directory
static DIR     dh;
static FILINFO fi;
static int     fiCont = 0;
static FIL     fh;
static char    fbuf[MAX_STRING_LENGTH + 2];

extern cfg_t CFG;

// collect a flit
void usbint_recv_flit(const unsigned char *in, int length) {
    // copy up to remaining bytes
    unsigned bytesRead = min(length, USB_BLOCK_SIZE - recv_buffer_offset);
    memcpy(recv_buffer + recv_buffer_offset, in, bytesRead);
    recv_buffer_offset += bytesRead;
    
    if (recv_buffer_offset == USB_BLOCK_SIZE) {
        usbint_recv_block();
        
        // copy any remaining bytes
        memcpy(recv_buffer, in + bytesRead, length - bytesRead);
        recv_buffer_offset = length - bytesRead;
    }
}

void usbint_recv_block(void) {
    static int cmdDat = 0;
    static uint32_t count = 0;
    
    // check header
    if (!cmdDat) {
        // command operations
        //PRINT_MSG("[ cmd]");
 
        if (recv_buffer[0] == 'U' && recv_buffer[1] == 'S' && recv_buffer[2] == 'B' && recv_buffer[3] == 'A') {            
            if (recv_buffer[4] == USBINT_SERVER_OPCODE_PUT || recv_buffer[4] == USBINT_SERVER_OPCODE_EXE) {
                // put operations require
                cmdDat = 1;
            }
            //PRINT_FUNCTION();
            //PRINT_MSG("[ cmd]");
            
            // FIXME: this needs to have release semantics
            //if (server_state != USBINT_SERVER_STATE_HANDLE_LOCK || recv_buffer[4] == USBINT_SERVER_OPCODE_MENU_UNLOCK) {
            //PRINT_STATE(server_state);
            server_state = USBINT_SERVER_STATE_HANDLE_CMD;
            //PRINT_STATE(server_state);

            //PRINT_CMD(recv_buffer);
            //PRINT_END();
        }
    }
    else {
        // data operations

        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            //server_info.offset += file_writeblock(recv_buffer, server_info.offset, USB_BLOCK_SIZE);
            UINT bytesRecv = 0;
            server_info.error |= f_lseek(&fh, count);
            do {
                UINT bytesWritten = 0;
                server_info.error |= f_write(&fh, recv_buffer + bytesRecv, USB_BLOCK_SIZE - bytesRecv, &bytesWritten);
                bytesRecv += bytesWritten;
                //server_info.offset += bytesWritten;
                count += bytesWritten;
            } while (bytesRecv != USB_BLOCK_SIZE && count < server_info.size);
        }
        else {
            // write SRAM
            UINT blockBytesWritten = 0;
            do {
                UINT bytesWritten = 0;
                UINT remainingBytes = min(USB_BLOCK_SIZE - blockBytesWritten, server_info.size - count);
                bytesWritten = sram_writeblock(recv_buffer, server_info.offset + count, remainingBytes);
                blockBytesWritten += bytesWritten;
                count += bytesWritten;
            } while (blockBytesWritten != USB_BLOCK_SIZE && count < server_info.size);
            
            // FIXME: figure out how to copy recv_buffer somewhere
            //count += USB_BLOCK_SIZE;
        }
        
        if (count >= server_info.size) {
            if (server_info.space == USBINT_SERVER_SPACE_FILE) {
                f_close(&fh);
            }
            //PRINT_FUNCTION();
            //PRINT_MSG("[ dat]");

            // unlock any sram transfer lock
            //PRINT_STATE(server_state);
            if (server_info.flags & USBINT_SERVER_FLAGS_SETX) {
                // enable hook
                server_state = USBINT_SERVER_STATE_HANDLE_EXE;
            }
            else if (server_state == USBINT_SERVER_STATE_HANDLE_LOCK) {
                server_state = USBINT_SERVER_STATE_IDLE;
            }            
            //PRINT_STATE(server_state);

            //PRINT_DAT((int)count, (int)server_info.size);

            cmdDat = 0;
            count = 0;
            
            //PRINT_END();
        }
        
   }
    
}

// send a block
void usbint_send_block(int blockSize) {
    // FIXME: don't need to double buffer anymore if using interrupt
    while(CDC_block_send((unsigned char*)send_buffer[send_buffer_index], blockSize) == -1) { }
    send_buffer_index = (send_buffer_index + 1) & 0x1;
}

int usbint_server_busy() {
    // LCK isn't considered busy
    return server_state == USBINT_SERVER_STATE_HANDLE_CMD || server_state == USBINT_SERVER_STATE_HANDLE_DAT || server_state == USBINT_SERVER_STATE_HANDLE_DATPUSH || server_state == USBINT_SERVER_STATE_HANDLE_EXE;
}

int usbint_server_dat() {
    // LCK isn't considered busy
    return server_state == USBINT_SERVER_STATE_HANDLE_DAT;
}

int usbint_server_reset() { return reset_state; }

// top level state machine
int usbint_handler(void) {
  int ret = 0;

  // *interrupt
  // make sure we can fill something
  //if (CDC_BulkIn_occupied()) { return; }
  
    switch(server_state) {
        case USBINT_SERVER_STATE_IDLE:       ret = usbint_handler_req(); break; 
        case USBINT_SERVER_STATE_HANDLE_CMD: ret = usbint_handler_cmd(); break;
        // **interrupt
        case USBINT_SERVER_STATE_HANDLE_DATPUSH: ret = usbint_handler_dat(); break;
        case USBINT_SERVER_STATE_HANDLE_EXE: ret = usbint_handler_exe(); break;
                
        default: break;
    }
        
  return ret;
}

int usbint_handler_cmd(void) {
    int ret = 0;
    uint8_t *fileName = recv_buffer + 256;

    PRINT_FUNCTION();
    PRINT_MSG("[hcmd]");
    
    // decode command
    server_info.opcode = recv_buffer[4];
    server_info.space = recv_buffer[5];
    server_info.flags = recv_buffer[6];

    server_info.size  = recv_buffer[252]; server_info.size <<= 8;
    server_info.size |= recv_buffer[253]; server_info.size <<= 8;
    server_info.size |= recv_buffer[254]; server_info.size <<= 8;
    server_info.size |= recv_buffer[255]; server_info.size <<= 0;

    server_info.offset = 0;
    server_info.error = 0;

    memset((unsigned char *)send_buffer[send_buffer_index], 0, USB_BLOCK_SIZE);

    switch (server_info.opcode) {
    case USBINT_SERVER_OPCODE_GET: {
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            fi.lfname = fbuf;
            fi.lfsize = MAX_STRING_LENGTH;
            server_info.error |= f_stat((TCHAR*)fileName, &fi);
            server_info.size = fi.fsize;
            server_info.error |= f_open(&fh, (TCHAR*)fileName, FA_READ);
        }
        else {
            server_info.offset  = recv_buffer[256]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[257]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[258]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[259]; server_info.offset <<= 0;
        }
        break;
    }
    case USBINT_SERVER_OPCODE_PUT: {
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            // file
            server_info.error = f_open(&fh, (TCHAR*)fileName, FA_WRITE | FA_CREATE_ALWAYS);
        }
        else {
            server_info.offset  = recv_buffer[256]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[257]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[258]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[259]; server_info.offset <<= 0;
        }
        break;
    }
    case USBINT_SERVER_OPCODE_LS: {
        fiCont = 0;
        fi.lfname = fbuf;
        fi.lfsize = MAX_STRING_LENGTH;
        server_info.error |= f_opendir(&dh, (TCHAR *)fileName) != FR_OK;
        server_info.size = 1;
        break;
    }
    case USBINT_SERVER_OPCODE_MKDIR: {
        server_info.error |= f_mkdir((TCHAR *)fileName) != FR_OK;
        break;
    }
    case USBINT_SERVER_OPCODE_RM: {
        server_info.error |= f_unlink((TCHAR *)fileName) != FR_OK;
        break;
    }
    case USBINT_SERVER_OPCODE_RESET: {
        snes_reset_pulse();
        break;
    }
    case USBINT_SERVER_OPCODE_MENU_RESET: {
        snes_reset_pulse();
        break;
    }
    case USBINT_SERVER_OPCODE_TIME: {
        struct tm time;

        time.tm_sec = (uint8_t) recv_buffer[4];
        time.tm_min = (uint8_t) recv_buffer[5];
        time.tm_hour = (uint8_t) recv_buffer[6];
        time.tm_mday = (uint8_t) recv_buffer[7];
        time.tm_mon = (uint8_t) recv_buffer[8];
        time.tm_year = (uint16_t) ((recv_buffer[9] << 8) + recv_buffer[10]);
        time.tm_wday = (uint8_t) recv_buffer[11];
					  
        set_rtc(&time);
    }
    case USBINT_SERVER_OPCODE_MV: {
        // copy string name
        strncpy((TCHAR *)fbuf, (TCHAR *)fileName, MAX_STRING_LENGTH);
        char *newFileName = fbuf;
        // remove the basename
        if ((newFileName = strrchr(newFileName, '/'))) *(newFileName + 1) = '\0';
        newFileName = fbuf;
        // add the new basename
        strncat((TCHAR *)newFileName, (TCHAR *)recv_buffer + 8, MAX_STRING_LENGTH - 8 - strlen(fbuf));
        // perform move
        server_info.error |= f_rename((TCHAR *)fileName, (TCHAR *)newFileName) != FR_OK;
        break;
    }
    case USBINT_SERVER_OPCODE_EXE: {
        // generate response.  check size for error
        server_info.offset  = recv_buffer[256]; server_info.offset <<= 8;
        server_info.offset |= recv_buffer[257]; server_info.offset <<= 8;
        server_info.offset |= recv_buffer[258]; server_info.offset <<= 8;
        server_info.offset |= recv_buffer[259]; server_info.offset <<= 0;
        server_info.error = (server_info.size > 0x9D);
        break;
    }
    case USBINT_SERVER_OPCODE_ATOMIC: // unsupported
    default: // unrecognized
        server_info.error = 1;
    case USBINT_SERVER_OPCODE_BOOT:
    case USBINT_SERVER_OPCODE_MENU_LOCK:
    case USBINT_SERVER_OPCODE_MENU_UNLOCK:
        // nop
        break;
    }

    // clear the execution cheats
    if (!server_info.error && (server_info.flags & USBINT_SERVER_FLAGS_CLRX)) {
        fpga_set_snescmd_addr(SNESCMD_WRAM_CHEATS);
        fpga_write_snescmd(ASM_RTS);

        // FIXME: this is a hack.  add a proper spinloop with status bit
        // wait to make sure we are out of the code.  one frame should do
        // could add a data region and wait for the write
        sleep_ms(16);
    }
    
    // boot the ROM
    if (server_info.opcode == USBINT_SERVER_OPCODE_BOOT) {
        // manually control reset in case we want to patch
        if (!(server_info.flags & USBINT_SERVER_FLAGS_ONLYRESET)) {
            strncpy ((char *)file_lfn, (char *)fileName, 256);
            cfg_add_last_game(file_lfn);
            // assert reset before loading
            assert_reset();
            // there may not be a menu to interact with so don't wait for SNES
            load_rom(file_lfn, 0, LOADROM_WITH_SRAM | LOADROM_WITH_FPGA /*| LOADROM_WAIT_SNES*/);
            //assert_reset();
            init(file_lfn);
            reset_state = 1;
        }               

        if (!(server_info.flags & USBINT_SERVER_FLAGS_SKIPRESET)) {
            deassert_reset();
            // enter the game loop like the menu would
            ret = SNES_CMD_GAMELOOP;
            reset_state = 0;
        }
    }
    
    PRINT_STATE(server_state);
    // decide next state
    if (server_info.opcode == USBINT_SERVER_OPCODE_GET || server_info.opcode == USBINT_SERVER_OPCODE_LS) {
        // we lock on data transfers so use interrupt for everything
        server_state = USBINT_SERVER_STATE_HANDLE_DAT;
    }
    else if (server_info.opcode == USBINT_SERVER_OPCODE_MENU_LOCK) {
        server_state = USBINT_SERVER_STATE_HANDLE_LOCK;
    }
    else if (server_info.opcode == USBINT_SERVER_OPCODE_EXE) {
        server_state = USBINT_SERVER_STATE_HANDLE_LOCK;
    }
    else if (server_info.opcode == USBINT_SERVER_OPCODE_PUT/* && server_info.space == USBINT_SERVER_SPACE_SNES*/) {
        server_state = USBINT_SERVER_STATE_HANDLE_LOCK;
    }
    else {
        server_state = USBINT_SERVER_STATE_IDLE;
    }
    PRINT_STATE(server_state);
    
    PRINT_CMD(recv_buffer);
    
    if (server_info.opcode == USBINT_SERVER_OPCODE_BOOT) {
        printf("Boot name: %s ", (char *)file_lfn);        
    }

    PRINT_END();

    // create response
    send_buffer[send_buffer_index][0] = 'U';
    send_buffer[send_buffer_index][1] = 'S';
    send_buffer[send_buffer_index][2] = 'B';
    send_buffer[send_buffer_index][3] = 'A';
    // opcode
    send_buffer[send_buffer_index][4] = USBINT_SERVER_OPCODE_RESPONSE;
    // error
    send_buffer[send_buffer_index][5] = server_info.error;
    // size
    send_buffer[send_buffer_index][252] = (server_info.size >> 24) & 0xFF;
    send_buffer[send_buffer_index][253] = (server_info.size >> 16) & 0xFF;
    send_buffer[send_buffer_index][254] = (server_info.size >>  8) & 0xFF;
    send_buffer[send_buffer_index][255] = (server_info.size >>  0) & 0xFF;
     
    // send response
    usbint_send_block(USB_BLOCK_SIZE);
 
    // lock process.  this avoids a conclusion with the rest of the menu accessing the file system or sram
    while(server_state == USBINT_SERVER_STATE_HANDLE_LOCK || server_state == USBINT_SERVER_STATE_HANDLE_DAT) {};
    
    return ret;

}

int usbint_handler_dat(void) {
    int ret = 0;
    static int count = 0;
    int bytesSent = 0;
    
    // if there is no data to send, do not call the send function so the CDC function is no longer called
    //if (server_state != USBINT_SERVER_STATE_HANDLE_DAT && server_state != USBINT_SERVER_STATE_HANDLE_DATPUSH) return;
    
    switch (server_info.opcode) {
    case USBINT_SERVER_OPCODE_GET: {
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            server_info.error |= f_lseek(&fh, server_info.offset + count);
            do {
                UINT bytesRead = 0;
                server_info.error |= f_read(&fh, (unsigned char *)send_buffer[send_buffer_index] + bytesSent, USB_DATABLOCK_SIZE - bytesSent, &bytesRead);
                bytesSent += bytesRead;
                count += bytesRead;
            } while (bytesSent != USB_DATABLOCK_SIZE && count < server_info.size);

            // close file
            if (count >= server_info.size) {
                f_close(&fh);
            }
        }
        else {
            do {
                UINT bytesRead = 0;
                bytesRead = sram_readblock((uint8_t *)send_buffer[send_buffer_index] + bytesSent, SRAM_ROM_ADDR + server_info.offset + count, USB_DATABLOCK_SIZE - bytesSent);
                bytesSent += bytesRead;
                count += bytesRead;
            } while (bytesSent != USB_DATABLOCK_SIZE && count < server_info.size);
        }

        break;
    }
    case USBINT_SERVER_OPCODE_LS: {
        uint8_t *name = NULL;
        do {
            int fiContPrev = fiCont;
            fiCont = 0;
            
            /* Read the next entry */
            if (server_info.error || (!fiContPrev && f_readdir(&dh, &fi) != FR_OK)) {
                send_buffer[send_buffer_index][bytesSent++] = 0xFF;
                count = 1; // signal done
                f_closedir(&dh);
                break;
            }

            /* Abort if none was found */
            if (!fi.fname[0]) {
                send_buffer[send_buffer_index][bytesSent++] = 0xFF;
                count = 1; // signal done
                f_closedir(&dh);
                break;
            }

            /* Skip volume labels */
            if (fi.fattrib & AM_VOL)
                continue;

            /* Select between LFN and 8.3 name */
            if (fi.lfname[0]) {
                name = (uint8_t*)fi.lfname;
            }
            else {
                name = (uint8_t*)fi.fname;
                strlwr((char *)name);
            }

            // check for id(1) string(strlen + 1) is does not go past index
            if (bytesSent + 1 + strlen((TCHAR*)name) + 1 <= USB_DATABLOCK_SIZE) {
                send_buffer[send_buffer_index][bytesSent++] = (fi.fattrib & AM_DIR) ? 0 : 1;
                strcpy((TCHAR*)send_buffer[send_buffer_index] + bytesSent, (TCHAR*)name);
                bytesSent += strlen((TCHAR*)name) + 1;
                // send string
            }
            else {
                // send continuation.  overwrite string flag to simplify parsing
                send_buffer[send_buffer_index][bytesSent++] = 2;
                fiCont = 1;
                break;
            }
        } while (bytesSent < USB_DATABLOCK_SIZE);
        break;
    }
    default: {
        // send back a single data beat with all 0xFF's
        memset((unsigned char *)send_buffer[send_buffer_index], 0xFF, USB_DATABLOCK_SIZE);
        bytesSent = USB_DATABLOCK_SIZE;
        break;
    }
    }
    
    if (count >= server_info.size) {
        // clear out any remaining portion of the buffer
        memset((unsigned char *)send_buffer[send_buffer_index] + bytesSent, 0x00, USB_DATABLOCK_SIZE - bytesSent);
    }
    
    // **interrupt
    if (server_state == USBINT_SERVER_STATE_HANDLE_DATPUSH) {
        usbint_send_block(USB_DATABLOCK_SIZE);
    }
    else {
        CDC_block_init((unsigned char*)send_buffer[send_buffer_index], USB_DATABLOCK_SIZE);
        send_buffer_index = (send_buffer_index + 1) & 0x1;
    }

    // printing state seems to cause some locks
    //PRINT_STATE(server_state);
    if (count >= server_info.size) {
        //PRINT_FUNCTION();
        //PRINT_MSG("[hdat]")

        //PRINT_STATE(server_state);
        server_state = USBINT_SERVER_STATE_IDLE;
        //PRINT_STATE(server_state);

        //PRINT_DAT((int)count, (int)server_info.size);
        
        count = 0;

        //PRINT_END();
    }    
    
    return ret;
}

int usbint_handler_req(void) {
    int ret = 0;
    //static uint16_t control = 0;
    
    // read the status register
    uint16_t status = fpga_status();
    if (status & USB_FPGA_STATUS_ALL_FLAG_BIT) {
        // check if any flags are set
        
        // check if we transition to disconnected at any point
        // TODO: handle the race for an inflight access.
        // - No good way to do this with the current busy bit definition.  Could force a timeout on busy on the FPGA.
        // - We could handle it here in the firmware.  Basically, disconnected only serves as a status bit to SNES.  We need to handle
        //   all transitions here so reads and writes complete.
        
        // first look at the control
        if (status & USB_FPGA_STATUS_CTRL_FLAG_BIT) {
            // get the new control information
            //control = get_usb_ctrl();
            
            //set_usb_status(USB_SNES_STATUS_CLEAR_CTRL);
        }
                
        // check if we need to send a read
        
        // check if we need to send a write
    }
    
    return ret;
}

int usbint_handler_exe(void) {
    int ret = 0;

    PRINT_FUNCTION();
    PRINT_MSG("[hexe]")
    
    if (!server_info.error) {
        // disable current hooks
        //cheat_wram_present(0);
        //snescmd_prepare_nmihook();

        //cheat_enable(0);
        //cheat_nmi_enable(0);
        //cheat_irq_enable(0);
        //cheat_wram_present(0);
        
        // write SRAM
        //sram_writeblock(recv_buffer, SRAM_CHEAT_ADDR, server_info.size);
        
        // clear out existing patch by overwriting with a RTS
        fpga_set_snescmd_addr(SNESCMD_WRAM_CHEATS);
        fpga_write_snescmd(ASM_RTS);
        
        // wait to make sure we are out of the code.  one frame should do
        // could add a data region and wait for the write
        sleep_ms(16);
        
        for (int i = 1; i < server_info.size; i++) {
            uint8_t val = sram_readbyte(server_info.offset + i);
            fpga_write_snescmd(val);
        }
        // write RTS
        fpga_write_snescmd(ASM_RTS);

        fpga_set_snescmd_addr(SNESCMD_WRAM_CHEATS);
        fpga_write_snescmd(sram_readbyte(SRAM_CHEAT_ADDR));
        
        // unlock the address range so the patch can remove itself
        //fpga_set_features(romprops.fpga_features | FEAT_CMD_UNLOCK);
        
        //snescmd_writebyte(1, SNESCMD_NMI_WRAM_PATCH_COUNT);
        //fpga_write_cheat(6, 0);
        //cheat_enable(1);
        //cheat_nmi_enable(1);
        //cheat_irq_enable(1);
        //cheat_holdoff_enable(CFG.enable_irq_holdoff);
        //cheat_buttons_enable(CFG.enable_irq_buttons);
        //cheat_wram_present(1);
    }
    
    PRINT_STATE(server_state);
    server_state = USBINT_SERVER_STATE_IDLE;
    PRINT_STATE(server_state);

    PRINT_END();
    
    return ret;
}
