void append_usbbuffer(const unsigned char *in, int length);
//int read_usbbuffer(unsigned char *sdram_chunk);
int send_sdram_to_host(void);
void usb_handler(void);
void usb_boot(void);
void reset_usb_vars(void);
