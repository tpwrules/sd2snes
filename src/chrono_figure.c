/* sd2snes - SD card based universal cartridge for the SNES
   Copyright (C) 2009-2010 Maximilian Rehkopf <otakon@gmx.net>
   uC firmware portion

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

   chrono_figure.c: interface functions for Chrono Figure FPGA logic
*/

/*

THE CHRONO FIGURE ADDRESS SPACE

The easiest way to interface with the USB code appears to be to pretend to be a
memory. We have our own space (USBINT_SERVER_SPACE_CHRONO_FIGURE), so we set it
up so that executing PUT and GET opcodes over the USB interface calls
cf_writeblock and cf_readblock.

The address space is very 32-bit little endian, so only 32-bit reads and writes
are supported to 32-bit aligned addresses. However, cf_writeblock and
cf_readblock have to emulate this for byte accesses. This has some
considerations outlined below.

For cf_readblock, there is a 32-bit word cache which stores the last accessed
word and its word address. If a new access happens to a different word address,
the cache is loaded with that new word and any read side effects take place.

For cf_writeblock, there is another 32-bit word cache which stores the last
written word, its word address, and which bytes within were written. Once all
four bytes have been written, the write is performed and any write side effects
take place. If a different word address is written to, or if any write is
performed, the cache is cleared and the data is forgotten.

The functions are designed so that reading and writing linearly, even in weird
sized chunks, works as expected. "Linearly" being that the address of the next
operation is the address of the previous operation + the amount of bytes
operated on in that operation. This is how the USB code uses it.

The address space is as follows. Writes to addresses not listed have no effect,
and reads from such addresses produce zero.
0x00000000          (R  ): gateware version

0x00000004          (R/W): loopback register (reads as the last value written)

0x00000008          (  W): reset control. write nonzero to assert console reset
                           or zero to deassert. the sd2snes will not notice the
                           reset so e.g. SRAM will not be saved. cleared on ROM
                           load.

0x0000000C          (  W): save inhibit. write nonzero to stop the sd2snes from
                           saving save RAM. write zero to re-enable saving and
                           force one save. cleared on ROM load.

0x00000010          (  W): save RAM clear. write 0x05C1EA12 to clear save RAM
                           (set all bytes to 0xFF). may have "exciting" effects
                           if not in reset.

0x10000000-1FFFFFFF (  W): matcher config registers. currently there is one word
                           per matcher and 256 words mapped in the space (but
                           not necessarily 256 matchers), with the rest as
                           mirrors.

0x80000000-8FFFFFFF (R  ): event FIFO. reading any address returns the next word
                           from the FIFO. if the high bit is set, then the FIFO
                           was empty and the word is invalid.

*/

#include <inttypes.h>
#include <string.h>
#include "chrono_figure.h"
#include "fpga_spi.h"
#include "snes.h"
#include "memory.h"
#include "smc.h"

extern snes_romprops_t romprops;

volatile uint8_t cf_is_hiding_reset = 0;
volatile uint8_t cf_save_inhibit = 0;

uint32_t cf_get_gateware_version() {
  FPGA_SELECT();
  FPGA_TX_BYTE(FPGA_CMD_CF_GET_GW_VER);

  uint32_t version = (uint32_t)(FPGA_RX_BYTE());
  version |= ((uint32_t)(FPGA_RX_BYTE())) << 8;
  version |= ((uint32_t)(FPGA_RX_BYTE())) << 16;
  version |= ((uint32_t)(FPGA_RX_BYTE())) << 24;
  FPGA_DESELECT();

  return version;
}

uint32_t cf_read_event() {
  FPGA_SELECT();
  FPGA_TX_BYTE(FPGA_CMD_CF_READ_EVENT);
  FPGA_RX_BYTE(); // dummy to read the FIFO

  uint32_t event = (uint32_t)(FPGA_RX_BYTE());
  event |= ((uint32_t)(FPGA_RX_BYTE())) << 8;
  event |= ((uint32_t)(FPGA_RX_BYTE())) << 16;
  event |= ((uint32_t)(FPGA_RX_BYTE())) << 24;
  FPGA_DESELECT();

  return event;
}

void cf_write_config(uint8_t addr, uint32_t value) {
  FPGA_SELECT();
  FPGA_TX_BYTE(FPGA_CMD_CF_WRITE_CONFIG);
  FPGA_TX_BYTE(addr);
  FPGA_TX_BYTE((value) & 0xFF);
  FPGA_TX_BYTE((value >> 8) & 0xFF);
  FPGA_TX_BYTE((value >> 16) & 0xFF);
  FPGA_TX_BYTE((value >> 24) & 0xFF);
  FPGA_DESELECT();
}

static uint32_t loopback_register = 0;

static uint32_t cf_readword(uint32_t addr) {
   switch(addr >> 28) {
      case 0x0:
         switch(addr) {
            case 0x00000000:
               return cf_get_gateware_version();
            case 0x00000004:
               return loopback_register;
            default:
               return 0;
         }
      case 0x8:
         return cf_read_event();
      default:
         return 0;
   }
}

static void cf_writeword(uint32_t addr, uint32_t value) {
   switch(addr >> 28) {
      case 0x0:
         switch(addr) {
            case 0x00000004:
               loopback_register = value;
               break;
            case 0x00000008:
               cf_is_hiding_reset = (value != 0) ? 1 : 0;
               snes_reset(cf_is_hiding_reset);
               break;
            case 0x0000000C:
               cf_save_inhibit = (value != 0) ? 1 : 0;
               break;
            case 0x00000010:
               if (value == 0x05C1EA12) {
                  sram_memset(SRAM_SAVE_ADDR, romprops.ramsize_bytes,
                     // if GSU is enabled, this gets set to 00 to fix an
                     // unreleased game. but does the emulator? chrono figure
                     // isn't supported on GSU anyway.
                     0xFF);
               }
         }
         break;
      case 0x1:
         cf_write_config(addr & 0xFF, value);
         break;
   }
}

uint32_t cf_readblock(void* buf, uint32_t addr, uint32_t size) {
   static uint32_t read_buf = 0;
   // address 1 is not possible so this means "nothing here yet" effectively
   static uint32_t read_addr = 1;

   if (size == 0) {
      return 0;
   }

   uint32_t num_read = size;

   // fill potentially non-aligned buffer start
   if ((addr & 3) != 0) {
      uint32_t word_addr = addr & 0xFFFFFFFC;
      if (word_addr != read_addr) {
         read_buf = cf_readword(word_addr);
         read_addr = word_addr;
      }
      while (((addr & 3) != 0) && (size > 0)) {
         // cortex-m is little endian
         *(uint8_t*)buf++ = ((uint8_t*)&read_buf)[addr & 3];
         addr++;
         size--;
      }
   }

   // do the aligned middle and non-aligned end
   while (size > 0) {
      read_addr = addr;
      read_buf = cf_readword(read_addr);
      if (size >= 4) { // enough room for a full word
         memcpy(buf, &read_buf, 4);
         buf += 4;
         addr += 4;
         size -= 4;
      } else {
         // store only the bit that will fit
         memcpy(buf, &read_buf, size);
         break;
      }
   }

   return num_read;
}

uint32_t cf_writeblock(void* buf, uint32_t addr, uint32_t size) {
   static uint32_t write_buf = 0;
   // address 1 is not possible so this means "nothing here yet" effectively
   static uint32_t write_addr = 1;
   static uint8_t written_bits = 0;

   if (size == 0) {
      return 0;
   }

   uint32_t num_written = size;

   // write potentially non-aligned buffer start
   if ((addr & 3) != 0) {
      uint32_t word_addr = addr & 0xFFFFFFFC;
      if (word_addr != write_addr) {
         write_addr = word_addr;
         written_bits = 0;
      }
      while (((addr & 3) != 0) && (size > 0)) {
         ((uint8_t*)&write_buf)[addr & 3] = *(uint8_t*)buf++;
         written_bits |= 1 << (addr & 3);
         addr++;
         size--;
      }
      if (written_bits == 0xF) {
         cf_writeword(write_addr, write_buf);
         write_addr = 1;
      }
   }

   if (size == 0) {
      return num_written;
   } else if (size > 3) {
      // we're going to write to the write buffer during the aligned middle, so
      // invalidate it
      write_addr = 1;
   }

   // do the aligned middle
   while (size > 3) {
      memcpy(&write_buf, buf, 4);
      cf_writeword(addr, write_buf);
      addr += 4;
      buf += 4;
      size -= 4;
   }

   // and finally the non-aligned end
   if (size > 0) {
      uint32_t word_addr = addr & 0xFFFFFFFC;
      if (word_addr != write_addr) {
         write_addr = word_addr;
         written_bits = 0;
      }
      while (size > 0) {
         ((uint8_t*)&write_buf)[addr & 3] = *(uint8_t*)buf++;
         written_bits |= 1 << (addr & 3);
         addr++;
         size--;
      }
      if (written_bits == 0xF) {
         cf_writeword(write_addr, write_buf);
         write_addr = 1;
      }
   }

   return num_written;
}
