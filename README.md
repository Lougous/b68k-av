
# Overview

This board provides audio and video capabilities to the b68k computer. Main components:
* CPLD for local bus decoding and FPGA configuration
* [flex FPGA](/doc/flex.md)
* SRAM 16-bits, 256kiB or 512 kiB
* video RAMDAC
* OPL2 audio chip

external interfaces: video (VGA, DIN 15 pins) and audio (3.5mm jack) 

# Memory mapping

The AVMGR CPLD decodes local bus accesses to address itself, the RAMDAC, the OPL2 or the flex FPGA.

| address range     | size   | memory area |
|:-----------------:|:------:|:-----:|
| 00000h  - 0007Fh  | 128B   | AVMGR registers. address bit 0 is ignored |
| 00080h  - 000FFh  | 128B   | flex registers |
| 00100h  - 0017Fh  | 128B   | RAMDAC registers. address bit 0 is ignored |
| 00180h  - 001FFh  | 128B   | OPL2 registers. address bit 0 is ignored |
| 00200h  - 07FFFh  | 512B*63 | mirrors x63 address range 000h-1FFh |
| 08000h -  0FFFFh  | 32kiB   | SRAM access (upper 32kiB, banking through flex register) |
| 10000h -  1FFFFh  | 64kiB   | SRAM access (banking through flex register) |

## AVMGR registers

These registers provide an interface to configure the flex FPGA. Address bit 0 is ignored, so that odd address target the same register as at even address.

| address offset    | name   | description |
|:-----------------:|:------:|:-----
| 00000h            | cfgnsts | bit 0: (r) flex nSTATUS signal<br>bit 1: (r) flex CONF_DONE signal<br>bit 6: (rw) flex nCONFIG signal<br>bit 7: (rw) flex reset signal (active low) |
| 00002h            | dat | bit 0: (rw) flex DAT0 signal<br>When this register is written, the flex DAT0 signal is driven and a pulse is generated on DCLK |
| 00004h            | dbg0 | spare register for debug purpose |
| 00006h            | dbg1 | spare register for debug purpose |

These registers mirror every 8 bytes.

## OPL2 registers

Provide access to the 2 OPL2 registers. Address bit 0 is ignored, so that odd address target the same register as at even address.

| address offset    | name   | description |
|:-----------------:|:------:|:-----
| 00000h            | regad | OPL2 Address (write) and status (read) register |
| 00002h            | regdt | OPL2 Data register |

## RAMDAC registers

Provide access to the RAMDAC registers (Bt476 / IMS G176 or compatible). Address bit 0 is ignored, so that odd address target the same register as at even address.

| address offset    | name   | description |
|:-----------------:|:------:|:-----
| 00000h            | ad_write | Address Register (RAM Write Mode) |
| 00002h            | color | Color Palette RAM |
| 00004h            | mask | Pixel read Mask Register |
| 00006h            | ad_read | Address Register (RAM Read Mode) |

## flex registers

See [flex FPGA](/doc/flex.md) documentation.
