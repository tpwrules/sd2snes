#include <stdio.h>
#include <string.h>
#include "fpga_spi.h"
#include "led.h"
#include "snes.h"
#include "timer.h"
#include "memory.h"
#include "usbhw.h"
#include "usbdesc.h"
#include "cdcuser.h"
#include "usbcfg.h"
#include "fileops.h"
#include "rtc.h"
#include "fpga.h"

volatile char loop_lock;
volatile unsigned int usb_filesize;
volatile uint8_t usb_handler_flags;
extern uint32_t saveram_crc_old;
volatile unsigned char send_buffer[2][512];
volatile unsigned char usb_filename[256];
//static volatile uint8_t usb_rec_request=0;
char disable_d4=0;
char fpga_reconf=0;
char dsp_support=0;
char booted=0;
char sending=0;
uint8_t send_buffer_index = 0;
//char ready_request=0;
//unsigned char send_stage=0;


void reset_usb_vars(void){
	
  loop_lock=0;
  usb_filesize=0;
  usb_handler_flags=0;
  disable_d4=0;
  fpga_reconf=0;
  booted=0;
  sending=0;
  //ready_request=0;
  //send_stage=0;	

}


int send_sdram_to_host(void){
  //uint8_t	sdram_chunk[512];
  static unsigned char send_stage=0;

  //static unsigned int bytes_left;
  static unsigned int bytes_offset=0;
  //requestet by usb host

  static DIR dh;
  static int index = 0;
  static FILINFO finfo;
  
  if(usb_handler_flags & (USB_SEND_ROM|USB_SEND_RAM|USB_SEND_DIR) ){
		
    //transfer size
    //usb_filesize
		
    //info pkt stage
    if(send_stage==0){
			
      //try sending first 512 byte
      //	printf("call CDC_block_send stage=%d size=%d\n",stage,sizeof(send_buffer[send_buffer_index]));
      while(CDC_block_send((unsigned char*)send_buffer[send_buffer_index], sizeof(send_buffer[send_buffer_index])) == -1) {}
      send_buffer_index = (send_buffer_index + 1) % 2;
      //printf("CDC_block_send exit stage=%d\n",stage);
      send_stage=1;

      //	bytes_left=usb_filesize;

				
    }else if(send_stage==1 ){//&& ready_request){ //data stage
				
      //block recall by bulk in event interrupt - untill client app is ready
      //	ready_request=0;
			
      if(usb_handler_flags & USB_SEND_ROM){
        sram_readblock((unsigned char*)send_buffer[send_buffer_index],  SRAM_ROM_ADDR+bytes_offset, 0x200);					
      }
      else if(usb_handler_flags & USB_SEND_RAM){					
        sram_readblock((unsigned char*)send_buffer[send_buffer_index], SRAM_SAVE_ADDR+bytes_offset, 0x200);
      }
      else if (usb_handler_flags & USB_SEND_DIR) {
        FRESULT res;
        uint8_t *name;
        int ok = 1;
        //strncpy(buf, usb_directory, 256);
        //f_getcwd((TCHAR*)buf, 255);

        usb_filesize = 0x7FFFFFFFL;
        index = 0;

        memset((unsigned char*)send_buffer[send_buffer_index], 0, 512);
        
        if (bytes_offset == 0) {
          res = f_opendir(&dh, (TCHAR*)usb_filename);
          finfo.lfname = (TCHAR*)usb_filename;
          finfo.lfsize = 255;

          if (res != FR_OK) {
            printf("f_opendir failed, result %d\n",res);
            send_buffer[send_buffer_index][index++] = 0xFF;
            usb_filesize = bytes_offset + 512;
            ok = 0;
          }
        }
        
        if (ok) {
          do {
            /* Read the next entry */
            res = f_readdir(&dh, &finfo);

            if (res != FR_OK) {
              printf("f_readdir failed, result %d\n",res);
              send_buffer[send_buffer_index][index++] = 0xFF;
              usb_filesize = bytes_offset + 512;
              f_closedir(&dh);
              break;
            }
          
            /* Abort if none was found */
            if (!finfo.fname[0]) {
              send_buffer[send_buffer_index][index++] = 0xFF;
              usb_filesize = bytes_offset + 512;
              f_closedir(&dh);
              break;
            }

            /* Skip volume labels */
            if (finfo.fattrib & AM_VOL)
              continue;

            /* Select between LFN and 8.3 name */
            if (finfo.lfname[0])
              name = (uint8_t*)finfo.lfname;
            else {
              name = (uint8_t*)finfo.fname;
              strlwr((char *)name);
            }

            // check for id(1) string(strlen + 1) is does not go past index
            if (index + 1 + strlen((TCHAR*)name) + 1 <= 512) {
              send_buffer[send_buffer_index][index++] = (finfo.fattrib & AM_DIR) ? 0 : 1;
              strcpy((TCHAR*)send_buffer[send_buffer_index] + index, (TCHAR*)name);
              index += strlen((TCHAR*)name) + 1;
              // send string
            }
            else {
              // send continuation.  overwrite string flag to simplify parsing
              send_buffer[send_buffer_index][index] = 2;
              break;
            }

            printf("\n");
          } while (index < 512);
        }
      }
				
      //wait for CDC_block_send to finish the last buffer
				
      while(CDC_block_send((unsigned char*)send_buffer[send_buffer_index], sizeof(send_buffer[send_buffer_index])) == -1);
      send_buffer_index = (send_buffer_index + 1) % 2;

      bytes_offset+=512;
				
      //datablock sent all done, reset all	
      if(bytes_offset>=usb_filesize){
					
        //memset(send_buffer[send_buffer_index], 0, 512);
        printf("usb: sending done...\n");
        //reset stage
        send_stage=0;
					
        //reset offsets
        bytes_offset=0;
					
        //info block size
        //bytes_left=0;
					
        //unlock usb_handler()
        usb_handler_flags=0;
					
        //stop sending
        sending=0;
        
        return 0; //sending done - free usb_handler
      }				
    }//stage 1 end
  }
  
  return 1;
}


void usb_send(uint8_t usb_flags){
	
  printf("usb_send()\n");

//  extern snes_romprops_t romprops;
//	
//  if(!booted) //not booted - maybe just a sram memory test - so generate header data
//    smc_id(&romprops, LOADROM_WITH_RESET | LOADROM_WITH_RAM);
//	
//  uint32_t rammask;
//  uint32_t rommask;
//	
//  if(romprops.header.ramsize == 0) {
//    rammask = 0;
//  } else {
//    rammask = romprops.ramsize_bytes;
//  }
//  rommask = romprops.romsize_bytes;
//	
//	
//  if(usb_flags & USB_SEND_ROM){
//    usb_filesize=rommask;
//  }
//	
//  if(usb_flags & USB_SEND_RAM){
//    usb_filesize=rammask;
//  }
	
  printf("usb_filesize %d\n", usb_filesize);	
	
  memset((unsigned char*)send_buffer[send_buffer_index], 0, 512);
				
  if(usb_flags & (USB_SEND_ROM|USB_SEND_RAM)){
    send_buffer[send_buffer_index][0]='F';
    send_buffer[send_buffer_index][1]='S';
    send_buffer[send_buffer_index][3] = (uint8_t) ((( usb_filesize) / 0x200) >> 8); //length
    send_buffer[send_buffer_index][4] = (uint8_t) (usb_filesize / 0x200); //length
    
    sending=1;
    //usb_rec_request=USB_SEND_ROM;
    //usb_handler_flags = USB_LOCK;
  }
  else if (usb_flags & USB_SEND_DIR) {
    sending = 1;
  }
}

void usb_boot(void){
	
  //extern snes_romprops_t romprops;

  printf("GO: usb boot\n");

  unsigned char filename[256];
  strcpy((TCHAR*)filename, (TCHAR*)usb_filename);
  load_rom(filename, 0, LOADROM_WITH_RESET | LOADROM_WITH_SRAM);

  // set next state for menu
  //snes_set_mcu_cmd(SNES_CMD_GAMELOOP);

//smc_id(&romprops, LOADROM_WITH_RESET | LOADROM_WITH_RAM);
//uint32_t rammask;
//uint32_t rommask;
//
//if(romprops.header.ramsize == 0) {
//  rammask = 0;
//} else {
//  rammask = romprops.ramsize_bytes - 1;
//}
//rommask = romprops.romsize_bytes - 1;
//
//if(fpga_reconf){
//  if(romprops.fpga_conf) {
//    printf("reconfigure FPGA with %s...\n", romprops.fpga_conf);
//    fpga_pgm((uint8_t*)romprops.fpga_conf);
//  }
//  set_mcu_addr(romprops.load_address);
//}
//
//if(dsp_support)
//  if(romprops.has_dspx) {
//    printf("DSPx game. Loading firmware image %s...\n", romprops.dsp_fw);
//    load_dspx(romprops.dsp_fw, romprops.fpga_features);
//    /* fallback to DSP1B firmware if DSP1.bin is not present */
//    if(file_res && romprops.dsp_fw == DSPFW_1) {
//      load_dspx(DSPFW_1B, romprops.fpga_features);
//    }
//    if(file_res) {
//      snes_menu_errmsg(MENU_ERR_SUPPLFILE, (void*)romprops.dsp_fw);
//    }
//  }
//      			
//printf("ramsize=%x rammask=%lx\nromsize=%x rommask=%lx\n", romprops.header.ramsize, rammask, romprops.header.romsize, rommask);
//printf("rom header map: %02x; mapper id: %d\n", romprops.header.map, romprops.mapper_id);
//      	
//      	
////disable for u16 boot
//if(disable_d4 == 1){
//  romprops.fpga_features &= ~FEAT_213F;
//}
//else{
//  romprops.fpga_features |= FEAT_213F;
//}
//      
//set_mapper(romprops.mapper_id);
//set_saveram_mask(rammask);
//set_rom_mask(rommask);
//      	
//
//      	
//if(romprops.ramsize_bytes) {
//  printf("has SRAM\n");
//      	
//  //should already be in memory at this point
//  //sram_memset(SRAM_SAVE_ADDR, romprops.ramsize_bytes, 0);
//  saveram_crc_old = calc_sram_crc(SRAM_SAVE_ADDR, romprops.ramsize_bytes);
//} else {
//      		
//  printf("No SRAM\n");
//}
//        
//      	
//fpga_set_213f(romprops.region);
//fpga_set_features(romprops.fpga_features);
//fpga_set_dspfeat(romprops.fpga_dspfeat);
//fpga_dspx_reset(1);
//snes_reset(1);
//delay_ms(SNES_RESET_PULSELEN_MS);
//snes_reset(0);
//fpga_dspx_reset(0);	
		
  usb_handler_flags = 0;
  booted=1;
		
}


void usb_handler(void){
  
  if(usb_handler_flags & USB_BOOT_ROM){
    usb_boot();
  }else
    if(usb_handler_flags & USB_SEND_ROM){
      if(!sending)
        usb_send(USB_SEND_ROM);
      else
        {
          printf("usb_handler() locked\n");
          //	snes_reset(1);
          while(send_sdram_to_host()) { };//sending 
          //	snes_reset(0);
          printf("usb_handler() unlocked\n");
        }
		
    }else
      if(usb_handler_flags & USB_SEND_RAM){
        if(!sending)
          usb_send(USB_SEND_RAM);
        else{
			
          printf("usb_handler() locked\n");
          //	snes_reset(1);
          while(send_sdram_to_host()) { };//sending 
          //	snes_reset(0);
          printf("usb_handler() unlocked\n");
			
        }
    }else
      if(usb_handler_flags & USB_SEND_DIR){
        if(!sending)
          usb_send(USB_SEND_DIR);
        else{
			
          printf("usb_handler() locked\n");
          //	snes_reset(1);
          while(send_sdram_to_host()) { };//sending 
          //	snes_reset(0);
          printf("usb_handler() unlocked\n");
			
        }
      }
	
  
  if(usb_handler_flags & USB_LOCK){
    printf("usb_handler() locked\n");
    while( usb_handler_flags & USB_LOCK){ };
    printf("usb_handler() unlocked\n");
  }
  
}

void append_usbbuffer(const unsigned char *in, int length){

  static uint8_t init=0; //first run
  static unsigned char buffer[512];
  static int offset=0;
  static uint8_t hold_reset=0;

  //maybe there is no really need for that
  if(init==0){
    memset(buffer, 0, 512);
    init=1;
  }

  static int datablocks=0;
  static int boffset=0;

  memcpy(buffer+offset, in, length);
  offset+=length;
       
  //copied to last offset -> 512 bytes available
  if(offset==0x200){ //512-64 process 512er buffer
    offset=0;
		   
    //data incoming, set offset and size
    if(datablocks==0){ //check for command pkt if no datablocks are incoming
			   
      //write command (data to offset)
      if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='W'){
        booted=0;
				   
        //optional speeds up a bit slightly - nothing more
        if(buffer[8] == 0x01){
          hold_reset = 0x1;
          snes_reset(1);
        }
						
        //lock main loop: dnd
        //required
        usb_handler_flags = USB_LOCK;
						
        //special offset operation
        boffset = (int) ((buffer[4] << 8) + buffer[5]);
        boffset *= 0x200;
						
        //savegame sram upload
        if(buffer[9] == 0x01)
          boffset += SRAM_SAVE_ADDR;
						
						
        if(buffer[11] == 0x01)
          fpga_reconf=1;
        else
          fpga_reconf=0;						
						
        if(buffer[12] == 0x01)
          dsp_support=1;
        else
          dsp_support=0;
						
						
        //for msu or
        strcpy ((TCHAR*)usb_filename, "usbfile");
        if(buffer[10] == 0x01){ //we have a rom or srm filename @255-510
          strcpy ((TCHAR*)usb_filename, (TCHAR*)buffer + 255);
        }											
						
        datablocks = (int) ((buffer[6] << 8) + buffer[7]);
        usb_filesize = datablocks*512;
        printf("usb: block offset: 0x%x \n", boffset );
        printf("usb: datablocks: %d  romsize: %d\n",datablocks, datablocks*512);

        // open the new file
        file_open((uint8_t *)usb_filename, FA_WRITE | FA_CREATE_ALWAYS);
									
        //datablocks-=1;	
        writeled(1);			
											
      } else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='D'){
        //directory list mode
				   					
        usb_handler_flags = USB_SEND_DIR;
        strcpy((TCHAR*)usb_filename, (TCHAR*)buffer + 255);
      }
      else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='R'){
        //read mode
				   
        //first USBR gets a 512byte filesize response
        //after that USBR is called fs/512 times to request every pkg
        //so the sd2snes isn't sending too fast, 'cause BULK_IN_STALL or CDC-BREAK
        //isn't implemented right atm.
				   
        //good enough for savegames and australia :D
				   
				   
				   
        //optional speeds up a bit slightly - nothing more
        /*
          if(buffer[5] == 0x01){
          hold_reset = 0x1;
          snes_reset(1);
          }
        */
					
        //in send_stage 0 the filesize pkg goes out and the usb_handler is going into send mode
        //if(send_stage==0){
					
        if (buffer[4]==0x01){ //ram
          usb_handler_flags = USB_SEND_RAM;
        }else
          if( buffer[4]==0x00){ //rom
            usb_handler_flags = USB_SEND_ROM;
          } 
        /*
          }else if(send_stage==1){
          //tool is ready for the next block
          ready_request=1;
          }
        */
      }
      //force unlock
      else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='U'){

        usb_handler_flags = 0;
        printf("usb: force unlock\n");

      }
      //force lock
      else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='L'){

        usb_handler_flags = USB_LOCK;
        printf("usb: force lock\n");
      }
      //set time
      else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='T'){
        struct tm time;

        time.tm_sec = (uint8_t) buffer[4];
        time.tm_min = (uint8_t) buffer[5];
        time.tm_hour = (uint8_t) buffer[6];
        time.tm_mday = (uint8_t) buffer[7];
        time.tm_mon = (uint8_t) buffer[8];
        time.tm_year = (uint16_t) ((buffer[9] << 8) + buffer[10]);
        time.tm_wday = (uint8_t) buffer[11];
					  
        set_rtc(&time);

        printf("usb: time set\n");
      }
      //mapper command
      else if(buffer[0]=='U' && buffer[1]=='S' && buffer[2]=='B' && buffer[3]=='B'){
						
        //security locks
        //snes_reset(1);
						
        if(buffer[4] == 0x01){
          disable_d4=1; //disable $213f-D4-region-patching
        }else{
          disable_d4=0; //set back
        }
						
        usb_handler_flags = USB_BOOT_ROM;
        strcpy((TCHAR*)usb_filename, (TCHAR*)buffer + 255);
        //snes_reset(0);

      }    
    }
    else { // datalocks incoming
      //sram_writeblock(buffer, boffset, 0x200);
      file_writeblock(buffer, boffset, 0x200);
				
      boffset+=0x200;
				
      //maybe not needed
				
      datablocks--;
				
      //if datablock is done, free main loop again
      if (datablocks==0) {
        writeled(0);
        //debug
        if(hold_reset==1){
          hold_reset=0;
          snes_reset(0);
        }

        file_close();
						
        usb_handler_flags = 0;
      }else{
        memset(buffer, 0, 512);
      } 		
    }
  }
}
