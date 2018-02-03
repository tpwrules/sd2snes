#include "config.h"
#include "fileops.h"
#include "uart.h"
#include "memory.h"
#include "fpga_spi.h"
#include "snes.h"
#include "yaml.h"
#include "cfg.h"

#include <string.h>
#include <stdlib.h>

extern cfg_t CFG;
extern snes_romprops_t romprops;

#define AM(idx, val) fpga_write_config(1, (idx), (val) & 0xFF, 0)
#define AM2(idx, val) AM(idx+0, ((val)>> 0)&0xFF); AM(idx+1, ((val)>> 8)&0xFF)
#define AM3(idx, val) AM(idx+0, ((val)>> 0)&0xFF); AM(idx+1, ((val)>> 8)&0xFF); AM(idx+2, ((val)>>16)&0xFF)
#define AM_DISABLE() for (int i = 0; i < 64; i += 8) { AM(i, 0xFF); }

struct AddrMapEntry {
  uint8_t  Mode; 
  unsigned Base;
  unsigned Mask;
  unsigned OBase;
  unsigned OMask;
};
typedef struct AddrMapEntry AddrMapEntry_t;

/* read cheats from YAML file to ROM for menu usage */
void addrmap_yaml_load(uint8_t* rompathname) {
  yaml_token_t token;
  char line[256];
  strncpy(line, (char *)rompathname, 255);
  strcpy(strrchr(line, (int)'.'), ".yml");

  printf("AddrMap YAML file: %s\n", line);
  yaml_file_open(line, FA_READ);
  if(file_res) {
    printf("no addrmap YML found\n");
  }
  else {
    AM_DISABLE();
  }
  /* read cheat entries */
  while(yaml_next_item()) {
    printf("AddrMap.yml: Checking for AddrMap: ");

    if (yaml_get_itemvalue("AddrMap", &token)) {
      printf("done.\n");

      printf("AddrMap.yml: Checking for list start token %d: ", token.type);
      if(token.type != YAML_LIST_START) break;
      printf("done.\n");
      
      // parse the address map entries of the form:
      // - [ Mode, Base, Mask, OBase, OMask ]
      // ...
      int addrmap_idx = 0;
      int i = 0;
      for(addrmap_idx=0; addrmap_idx < 8; addrmap_idx++) {
        AddrMapEntry_t entry;
        entry.Mode = 0xFF;
        entry.Base = 0;
        entry.Mask = 0;
        entry.OBase = 0;
        entry.OMask = 0;
        
        do {
          if(yaml_get_next(&token) == EOF) break;
          if(token.type == YAML_LIST_END) break;
         
          switch (i % 5) {
            case 0: entry.Mode = token.longvalue; break;
            case 1: entry.Base = token.longvalue; break;
            case 2: entry.Mask = token.longvalue; break;
            case 3: entry.OBase = token.longvalue; break;
            case 4: entry.OMask = token.longvalue; break;
            default: break;
          }
          i++;
        } while (i % 5 != 0);
        
        if (i % 5 != 0) break;
        
        // temporary workaround for timing problem - flip the bit manually
        printf("Parsed AddrMap: Mode=%02hhx, Base=%08x, Mask=%08x, OBase=%08x, OMask=%08x\n", entry.Mode, entry.Base, entry.Mask, entry.OBase, entry.OMask);
        AM(addrmap_idx*8+0, entry.Mode);
        AM2(addrmap_idx*8+1, entry.Base >> 8);
        AM2(addrmap_idx*8+4, entry.Mask >> 8);
        AM(addrmap_idx*8+3, entry.OBase >> 16);
        AM2(addrmap_idx*8+6, entry.OMask >> 8);
      }
    }
  }
  
  yaml_file_close();
  file_res = 0; /* soft fail, suppress LED blink */

  // read address map
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      uint8_t val = fpga_read_config(1, i * 8 + j);
      printf("%02hhx", val);
    }
    printf("\n");
  }
}

void addrmap_mapper(uint8_t val) {
  // read address map
  uint32_t rammask = romprops.ramsize_bytes == 0 ? 0 : romprops.ramsize_bytes - 1;
  uint32_t rommask = romprops.romsize_bytes == 0 ? 0 : romprops.romsize_bytes - 1;
  
  int index = 0;
  
  // program the menu address map
  AM_DISABLE();
  
  AM(index*8+0, 0xE0); AM2(index*8+1, 0x7E00); AM(index*8+3, 0x00); AM2(index*8+4, 0xFE00); AM2(index*8+6, 0x0000);
  index++;
  
  if (val == 0) {
      // hirom
      
      // 20-3F/A0-BF:6000-7FFF -> 0 (SaveRAM)
      if (rammask > 0) { AM(index*8+0, 0x23); AM2(index*8+1, 0x2060); AM(index*8+3, 0xE0); AM2(index*8+4, 0x60E0); AM2(index*8+6, rammask >> 8); index++; }
      // 00-3F:8000-FFFF, 40-7F:0000-FFFF -> 00:0000
      AM(index*8+0, 0x00); AM2(index*8+1, 0x0000); AM(index*8+3, 0x00); AM2(index*8+4, 0x8000); AM2(index*8+6, rommask >> 8);
      index++;
      // 80-BF:8000-FFFF, C0-FF:0000-FFFF -> 00:0000
      AM(index*8+0, 0x00); AM2(index*8+1, 0x8000); AM(index*8+3, 0x00); AM2(index*8+4, 0x8000); AM2(index*8+6, rommask >> 8);
      index++;
  }
  else if (val == 1) {
      // lorom
            
      // 70-7D:0000-7FFF -> 0 (SaveRAM)
      if (rammask > 0) {
          // ROMSize > 11 || SRAMSize > 5
          if (rommask >= 0x400000 || rammask >= 0x10000) {
            AM(index*8+0, 0x21); AM2(index*8+1, 0x7000); AM(index*8+3, 0xE0); AM2(index*8+4, 0x7080); AM2(index*8+6, rammask >> 8);
            index++;
          }
          else {
            AM(index*8+0, 0x20); AM2(index*8+1, 0x7000); AM(index*8+3, 0xE0); AM2(index*8+4, 0x7000); AM2(index*8+6, rammask >> 8);
            index++;
          }
      }
      // 00-3F:8000-FFFF -> 00:0000
      if (rommask >= 0x400000) {
        // assume 4MB inversion
        // first 4 MB -> $400000
        AM(index*8+0, 0x01); AM2(index*8+1, 0x0080); AM(index*8+3, 0x40); AM2(index*8+4, 0x8080); AM2(index*8+6, 0x3FFF);
        index++;
        // remaining -> $000000
        AM(index*8+0, 0x01); AM2(index*8+1, 0x8080); AM(index*8+3, 0x00); AM2(index*8+4, 0x8080); AM2(index*8+6, (rommask-0x400000) >> 8);
        index++;
      }
      else {
        AM(index*8+0, 0x01); AM2(index*8+1, 0x0080); AM(index*8+3, 0x00); AM2(index*8+4, 0x0080); AM2(index*8+6, rommask >> 8);
        index++;
      }
  }
  else if (val == 2) {
      // exthirom

      // 80-BF:6000-7FFF -> 0 (SaveRAM)
      if (rammask > 0) { AM(index*8+0, 0x23); AM2(index*8+1, 0x8060); AM(index*8+3, 0xE0); AM2(index*8+4, 0xC0E0); AM2(index*8+6, rammask >> 8); }
      index++;
      // 00-3F:8000-FFFF, 40-7F:0000-FFFF -> 00:0000
      AM(index*8+0, 0x00); AM2(index*8+1, 0x0000); AM(index*8+3, 0x40); AM2(index*8+4, 0x8000); AM2(index*8+6, 0x3FFF);
      index++;
      // 80-BF:8000-FFFF, C0-FF:0000-FFFF -> 00:0000
      AM(index*8+0, 0x00); AM2(index*8+1, 0x8000); AM(index*8+3, 0x00); AM2(index*8+4, 0x8000); AM2(index*8+6, (rommask-0x400000) >> 8);
      index++;
  }
  else if (val == 3) {
      // bs-x
      // handled by FPGA
  }
  else if (val == 6) {
      // star ocean

      // 20-3F/A0-BF:6000-7FFF -> 0 (SaveRAM)
      //if (rammask > 0) { AM(0*8+0, 0x2B); AM2(0*8+1, 0x2060); AM(0*8+3, 0xE0); AM2(0*8+4, 0x60E0); AM2(0*8+6, rammask >> 8); }
      // handled by FPGA... interleaves banks.
  }
  else if (val == 7) {
      // menu

      // F0-FF:0000-FFFF -> F0-FF:0000-FFFF (SaveRAM)
      AM(index*8+0, 0x28); AM2(index*8+1, 0xF000); AM(index*8+3, 0x00); AM2(index*8+4, 0xF000); AM2(index*8+6, 0xFFFF);
      index++;
      // * -> C0-EF:0000-FFFF
      AM(index*8+0, 0x00); AM2(index*8+1, 0x0000); AM(index*8+3, 0xC0); AM2(index*8+4, 0x0000); AM2(index*8+6, 0x3FFF);
      index++;
  }
  
  // read address map
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      uint8_t val = fpga_read_config(1, i * 8 + j);
      printf("%02hhx", val);
    }
    printf("\n");
  }
  printf("End AddrMap\n");
}