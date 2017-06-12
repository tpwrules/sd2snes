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

#define MAX_STRING_LENGTH 255

#define min(a,b) \
 ({ __typeof__ (a) _a = (a); \
 __typeof__ (b) _b = (b); \
 _a < _b ? _a : _b; })

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

enum usbint_server_state_e {
  USBINT_SERVER_STATE_IDLE = 0,
    
  USBINT_SERVER_STATE_HANDLE_CMD, // receive and decode request
  USBINT_SERVER_STATE_HANDLE_DAT, // receive data beats for writes
  USBINT_SERVER_STATE_HANDLE_LCK,

};

enum usbint_client_state_e {
  USBINT_CLIENT_STATE_IDLE = 0,
  
  USBINT_CLIENT_STATE_HANDLE_CMD,  // receive response
  USBINT_CLIENT_STATE_HANDLE_DAT,  // receive response data
  
};

enum usbint_server_opcode_e {
  // address space operations
  USBINT_SERVER_OPCODE_GET = 0,
  USBINT_SERVER_OPCODE_PUT,
  USBINT_SERVER_OPCODE_EXECUTE,
  USBINT_SERVER_OPCODE_ATOMIC,
  
  // file system operations
  USBINT_SERVER_OPCODE_LS,
  USBINT_SERVER_OPCODE_MKDIR,
  USBINT_SERVER_OPCODE_RM,
  USBINT_SERVER_OPCODE_MV,

  // special operations
  USBINT_SERVER_OPCODE_RESET,
  USBINT_SERVER_OPCODE_BOOT,
  USBINT_SERVER_OPCODE_MENU_LOCK,
  USBINT_SERVER_OPCODE_MENU_UNLOCK,
  USBINT_SERVER_OPCODE_MENU_RESET,
  USBINT_SERVER_OPCODE_EXE,
  USBINT_SERVER_OPCODE_TIME,
  
  // response
  USBINT_SERVER_OPCODE_RESPONSE,
};

enum usbint_server_space_e {
  USBINT_SERVER_SPACE_FILE = 0,
  USBINT_SERVER_SPACE_SNES,
};

enum usbint_server_flags_e {
  USBINT_SERVER_FLAGS_NONE = 0,  
  USBINT_SERVER_FLAGS_FAST = 1,  
};

volatile enum usbint_server_state_e server_state;

struct usbint_server_info_t {
  enum usbint_server_opcode_e opcode;
  enum usbint_server_space_e space;
  enum usbint_server_flags_e flags;
  
  uint32_t size;
  uint32_t offset;
  int error;
} server_info;

extern snes_romprops_t romprops;

unsigned recv_buffer_offset = 0;
unsigned char recv_buffer[USB_BLOCK_SIZE];

// double buffered because send only guarantees that a transfer is
// volatile since CDC needs to send it
uint8_t send_buffer_index = 0;
volatile unsigned char send_buffer[2][USB_BLOCK_SIZE];

// directory
static DIR     dh;
static FILINFO fi;
static FIL     fh;
static char    fbuf[MAX_STRING_LENGTH + 2];

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
    
    // check header
    if (!cmdDat) {
        // command operations
        if (recv_buffer[0] == 'U' && recv_buffer[1] == 'S' && recv_buffer[2] == 'B' && recv_buffer[3] == 'A') {            
            if (recv_buffer[4] == USBINT_SERVER_OPCODE_PUT) {
                // put operations require
                cmdDat = 1;
            }
            
            // FIXME: this needs to have release semantics
            if (server_state != USBINT_SERVER_STATE_HANDLE_LCK || recv_buffer[4] == USBINT_SERVER_OPCODE_MENU_UNLOCK) {
                server_state = USBINT_SERVER_STATE_HANDLE_CMD;
            }
        }
    }
    else {
        // data operations
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            //server_info.offset += file_writeblock(recv_buffer, server_info.offset, USB_BLOCK_SIZE);
            UINT bytesRecv = 0;
            server_info.error |= f_lseek(&fh, server_info.offset);
            do {
                UINT bytesWritten = 0;
                server_info.error |= f_write(&fh, recv_buffer + bytesRecv, USB_BLOCK_SIZE - bytesRecv, &bytesWritten);
                bytesRecv += bytesWritten;
                server_info.offset += bytesWritten;
            } while (bytesRecv != USB_BLOCK_SIZE && server_info.offset < server_info.size);
        }
        else {
            server_info.offset += sram_writeblock(recv_buffer, server_info.offset, USB_BLOCK_SIZE);
        }
        
        if (server_info.offset >= server_info.size) {
            if (server_info.space == USBINT_SERVER_SPACE_FILE) {
                f_close(&fh);
            }

            cmdDat = 0;
        }
    }
}

// send a block
void usbint_send_block(void) {
    while(CDC_block_send((unsigned char*)send_buffer[send_buffer_index], USB_BLOCK_SIZE) == -1) { }
    send_buffer_index = (send_buffer_index + 1) & 0x1;
}

int usbint_server_busy() {
    // LCK isn't considered busy
    return server_state == USBINT_SERVER_STATE_HANDLE_CMD || server_state == USBINT_SERVER_STATE_HANDLE_DAT;
}

// top level state machine
void usbint_handler(void) {
    // TODO: determine if the block is meant for the server or client
    usbint_handler_server();
}

void usbint_handler_server(void) {
    switch(server_state) {
        case USBINT_SERVER_STATE_HANDLE_CMD: usbint_handler_cmd(); break;
        case USBINT_SERVER_STATE_HANDLE_DAT: usbint_handler_dat(); break;
        default: break;
    }
}

void usbint_handler_cmd(void) {
    uint8_t *fileName = recv_buffer + 256;
    
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
            
            // temporarily copy the string to the response
            //strncpy((TCHAR*)send_buffer[send_buffer_index] + 256, (TCHAR*)fi.lfname, MAX_STRING_LENGTH - 128);
            //strncpy((TCHAR*)send_buffer[send_buffer_index] + 384, (TCHAR*)fileName, MAX_STRING_LENGTH - 128);
        }
        else if (server_info.space == USBINT_SERVER_SPACE_SNES) {
            server_info.offset  = recv_buffer[256]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[257]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[258]; server_info.offset <<= 8;
            server_info.offset |= recv_buffer[259]; server_info.offset <<= 0;
            server_info.size = 0x2000;
        }
        break;
    }
    case USBINT_SERVER_OPCODE_PUT: {
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            // file
            server_info.error = f_open(&fh, (TCHAR*)fileName, FA_WRITE | FA_CREATE_ALWAYS);
        }
        break;
    }
    case USBINT_SERVER_OPCODE_LS: {
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
    case USBINT_SERVER_OPCODE_EXE: // TODO
    case USBINT_SERVER_OPCODE_ATOMIC: // unsupported
    default: // unrecognized
        server_info.error = 1;
    case USBINT_SERVER_OPCODE_MENU_LOCK:
    case USBINT_SERVER_OPCODE_MENU_UNLOCK:
        // nop
        break;
    }

    // generate response
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
    
    usbint_send_block();

    // decide next state
    if (server_info.opcode == USBINT_SERVER_OPCODE_GET || server_info.opcode == USBINT_SERVER_OPCODE_LS) {
        server_state = USBINT_SERVER_STATE_HANDLE_DAT;
    }
    else if (server_info.opcode == USBINT_SERVER_OPCODE_MENU_LOCK) {
        server_state = USBINT_SERVER_STATE_HANDLE_LCK;
        while (server_state == USBINT_SERVER_STATE_HANDLE_LCK) {}
    }
    else {
        server_state = USBINT_SERVER_STATE_IDLE;
    }
    
    // try moving boot to the end to see if we avoid timeout
    if (server_info.opcode == USBINT_SERVER_OPCODE_BOOT) {
        load_rom(fileName, 0, LOADROM_WITH_RESET | LOADROM_WITH_SRAM);
    }

}

void usbint_handler_dat(void) {
    static int count = 0;
    int bytesSent = 0;
    
    switch (server_info.opcode) {
    case USBINT_SERVER_OPCODE_GET: {
        if (server_info.space == USBINT_SERVER_SPACE_FILE) {
            server_info.error |= f_lseek(&fh, server_info.offset + count);
            do {
                UINT bytesRead = 0;
                server_info.error |= f_read(&fh, (unsigned char *)send_buffer[send_buffer_index] + bytesSent, USB_BLOCK_SIZE - bytesSent, &bytesRead);
                bytesSent += bytesRead;
                count += bytesRead;
            } while (bytesSent != USB_BLOCK_SIZE && count < server_info.size);

            // close file
            if (count >= server_info.size) {
                f_close(&fh);
            }
        }
        else if (server_info.space == USBINT_SERVER_SPACE_SNES) {
            bytesSent = sram_readblock((uint8_t *)send_buffer[send_buffer_index], SRAM_ROM_ADDR + server_info.offset + count, USB_BLOCK_SIZE);
            count += bytesSent;
        }

        break;
    }
    case USBINT_SERVER_OPCODE_LS: {
        uint8_t *name = NULL;
        do {
            /* Read the next entry */
            if (server_info.error || f_readdir(&dh, &fi) != FR_OK) {
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
            if (bytesSent + 1 + strlen((TCHAR*)name) + 1 <= USB_BLOCK_SIZE) {
                send_buffer[send_buffer_index][bytesSent++] = (fi.fattrib & AM_DIR) ? 0 : 1;
                strcpy((TCHAR*)send_buffer[send_buffer_index] + bytesSent, (TCHAR*)name);
                bytesSent += strlen((TCHAR*)name) + 1;
                // send string
            }
            else {
                // send continuation.  overwrite string flag to simplify parsing
                send_buffer[send_buffer_index][bytesSent++] = 2;
                break;
            }

            printf("\n");
        } while (bytesSent < USB_BLOCK_SIZE);
        break;
    }
    default: {
        // send back a single data beat with all 0xFF's
        memset((unsigned char *)send_buffer[send_buffer_index], 0xFF, USB_BLOCK_SIZE);
        bytesSent = USB_BLOCK_SIZE;
        break;
    }
    }
    
    usbint_send_block();
    
    if (count >= server_info.size) {
        // clear out any remaining portion of the buffer
        memset((unsigned char *)send_buffer[send_buffer_index] + bytesSent, 0x00, USB_BLOCK_SIZE - bytesSent);
        count = 0;
        server_state = USBINT_SERVER_STATE_IDLE;
    }
}
