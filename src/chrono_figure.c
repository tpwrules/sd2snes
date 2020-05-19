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

#include <inttypes.h>
#include "chrono_figure.h"
#include "fpga_spi.h"

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
