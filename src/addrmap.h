#ifndef ADDRMAP_H
#define ADDRMAP_H

// AddrMap features
// - Programmable address map replaces hardcoded base ROM/SaveRAM addressing
// - YML file format supports game specific address map

#include <arm/NXP/LPC17xx/LPC17xx.h>

/* deploy address map to FPGA */
void addrmap_mapper(uint8_t val);
void addrmap_yaml_load(uint8_t *romfilename);

#endif
