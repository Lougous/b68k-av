The flex FPGA architecture is depicted hereafter:
![flex FPGA block diagram](/doc/flex.svg)

# local bus

## Read operations

All read accesses access a single status register:

| address offset    | name   | description |
|:-----------------:|:------:|:-----:|
| any               | status | bit 0: interrupt enable (active high)<br>bit 1: pending interrupt (active high)<br>bits 6..4: SRAM bank (8 banks x 64kiB = 512kiB)<br>7: GPU busy (active high) |

## Write operations (registers)

| address offset    | name   | description |
|:-----------------:|:------:|:-----:|
| 00080h            | itcgf  | bit 0: interrupt enable (active high)<br>bit 1: pending interrupt acknowlege (when written as 1) |
| 00081h            | bank   | bits 6..4: SRAM access bank (8 banks x 64kiB = 512kiB) |
| 00082h            | -      | spare |
| 00083h            | -      | spare |
| 00084h            | gpu0   | stop current buffer execution, if so, then set GPU command buffer address bits 8..1 |
| 00085h            | gpu1   | set GPU command buffer address bits 16..9, then start command buffer execution |
| 00086h            | -      | spare |
| 00087h            | -      | spare |

## Write operations (SRAM)

Write access to SRAM is controlled by the ''bank'' register, that defines which 64kiB section of the SRAM targets the write access into the address ranges listed below:

| address range     | size   | memory area |
|:-----------------:|:------:|:-----:|
| 08000h -  0FFFFh  | 32kiB  | SRAM access (upper 32kiB of current bank) |
| 10000h -  1FFFFh  | 64kiB  | SRAM access (full bank) |

# GPU

The GPU ables to perform basic 2D memory bloc move operations:
* READ operation: from SRAM to internal scratchpad memory (256 bytes, can be split in 4 banks of 64 bytes)
* WRITE operation: from internal scratchpad memory to SRAM.

READ/WRITE operations purpose is to draw 2D sprites. Sprites are 4-bits per pixels; as pixels in frame buffer are 8-bits, each sprite pixel is completed with an additional 4-bit value (that can be changed for each WRITE operation).

The sprite pixel value 0000b may be optionnaly considered as masked (not written).

Each operation can handle block size of 1 to 16 lines by 1 to 16 words wide, though multiple operations can be used to manage bigger sprites.

GPU commands are a list of 16-bits words, stored into lower 128-kiB in SRAM (00000h to 1FFFEh). Buffer must be 16-bits aligned.

To use the GPU, the usual sequence is:
* load/update graphic data to SRAM
* load/update command list in SRAM
* last command in the list must have the S flag to stop properly (see table below)
* start command list execution (registers ''gpu0''/''gpu1'')

GPU commands also able:
* to change the frame buffer address used by the video readback
* to change the frame buffer format used by the video readback
* to synchronize a command to the vertical refresh

<table>
  <thead>
    <tr>
      <th>15</th><th>14</th><th>13</th><th>12</th><th>11</th><th>10</th><th>9</th><th>8</th>
      <th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>0</td><td colspan=15>ADDR(14:0)</td>
    </tr>
    <tr>
      <td>1</td><td>0</td><td>-</td><td colspan=4>ADDR(18:15)</td><td>S</td><td colspan=4>HEIGHT(3:0)</td><td>F</td><td>LR</td><td>LP</td><td>WS</td>
    </tr>
    <tr>
      <td>1</td><td>1</td><td>-</td><td colspan=4>WIDTH(3:0)</td><td>RW</td><td>KY</td><td>-</td><td colspan=2>BK(1:0)</td><td colspan=4>LUT(3:0)</td>
    </tr>
  </tbody>
</table>

* ADDR:   SRAM address to read/write, or to set as frame buffer start address
* S:      stop display list execution when set
* F:      set frame buffer address/attributes when set
* LR:     Low res mode (validated by F)
* LP:     LUT in hi res mode (validated by F)
* WS:     when set with S, wait for next vertical synchro then resume command execution
* HEIGHT: pixel block height (line number, minus 1)
* WIDTH:  pixel block width (word number, minus 1)
* LUT:    pixel byte bits(7:4) for write (4-bits to 8-bits expansion)
* BK:     256 bytes scratchpad start address MSBs (00h, 40h, 80h, C0h)
* KY:     enable transparency during write with color key 0000b
* RW:     transfer direction: 0 for VRAM to scratchpad, 1 for scratchpad to VRAM

# video time base

The video time base generates video timing in respect to VGA video format to sequence the video readback operations.

# video readback

This function reads a frame buffer at a given start address in SRAM and provides pixel to the RAMDAC.

## pixel addressing

The start address may be changed through GPU command, though the new address will be considered at the next start of frame. Any start address in the two pages listed below can be used, but these rules apply:
* during horizontal pixel walk, the address 9 least significant bits only are incremented (within a 512 bytes segment)
* during vertical pixel walk, start address of line N+1 is start address of line N + 512 bytes, but rolls over within the page

These two rules ease the implementation of scrolling frame buffer content in both axis.

| address range     | size   | memory area |
|:-----------------:|:------:|:-----:|
| 00000h  - 1FFFFh  | 128kiB | not usable for readback |
| 20000h  - 3FFFFh  | 128kiB | page #0 |
| 00100h  - 0017Fh  | 128kiB | not usable for readback |
| 00180h  - 001FFh  | 128kiB | page #1 |

## pixel format

The readback supports 2 modes:
* low resolution mode; pixels are replicated so that an actual resolution of 320x240 pixels is used, yet still with a VGA (640x480) video timing. Each pixel is an 8-bits value that is used as an index into the color lookup table managed by the RAMDAC chip.
* high resolution mode; based on the 320x240x8-bits defined below, each 8-bit pixel is
  * if pixel MSB (bit 7) is set to zero, no change with low resolution mode (except that color index restricts to range 0..127)
  * if pixel MSB (bit 7) is set to one, the pixel is to be considered as a 2x2 pixel tile, thus possibly achieving an actual resolution of 640x480 pixels. Bits 3..0 provide a value for each pixel in the tile; bits 6..4 is used to form the 8-bits color index as detailed hereafter, together with pixel odd/even position over X and Y axis, as well as an additional LP bit (see GPU)

high resolution pixel expansion, upper-left pixel:
<table>
  <thead>
    <tr>
      <th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td><td>LP</td><td colspan=3>bits 6..4</td><td>0</td><td>0</td><td>bit 0</td>
    </tr>
  </tbody>
</table>

high resolution pixel expansion, upper-right pixel:
<table>
  <thead>
    <tr>
      <th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td><td>LP</td><td colspan=3>bits 6..4</td><td>0</td><td>1</td><td>bit 1</td>
    </tr>
  </tbody>
</table>

high resolution pixel expansion, lower-left pixel:
<table>
  <thead>
    <tr>
      <th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td><td>LP</td><td colspan=3>bits 6..4</td><td>1</td><td>0</td><td>bit 2</td>
    </tr>
  </tbody>
</table>

high resolution pixel expansion, lower-right pixel:
<table>
  <thead>
    <tr>
      <th>7</th><th>6</th><th>5</th><th>4</th><th>3</th><th>2</th><th>1</th><th>0</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td><td>LP</td><td colspan=3>bits 6..4</td><td>1</td><td>1</td><td>bit 3</td>
    </tr>
  </tbody>
</table>

# SRAM controller

Grants access to SRAM to (in priority order):
* readback (read only)
* local bus (write only)
* GPU (read / write)

# Audio

The flex FPGA decodes OPL2 output and generates a dual level PWM (6-bits x2, 12-bits precision in total). See ''audio_out_pwm_stereo'' sheet in board schematics for further details.

Both left and right channels output the same (OPL2 is mono).
