### Description

The ao486 is an x86 compatible Verilog core implementing all features of a 486 SX.
The core was modeled and tested based on the Bochs software x86 implementation.
Together with the 486 core, the ao486 project also contains a SoC capable of
booting the Linux kernel version 3.13 and Microsoft Windows 95.

### Current status
- 31 March 2014  - initial version 1.0.
- 19 August 2014 - driver_sd update, ps2 fix.

### Features

The ao486 processor model has the following features:
- pipeline architecture with 4 main stages: decode, read, execute and write,
- all 486 instructions are implemented, together with CPUID,
- 16 kB instruction cache,
- 16 kB write-back data cache,
- TLB for 32 entries,
- Altera Avalon interfaces for memory and io access.

The ao486 SoC consists of the following components:
- ao486 processor,
- IDE hard drive that redirects to a HDL SD card driver,
- floppy controller that also redirects to the SD card driver,
- 8259 PIC,
- 8237 DMA,
- Sound Blaster 2.0 with DSP and OPL2 (FM synthesis not fully working).
  Sound output redirected to a WM8731 audio codec,
- 8254 PIT,
- 8042 keyboard and mouse controller,
- RTC
- standard VGA.

All components are modeled as Altera Qsys components. Altera Qsys connects all
parts together, and supplies the SDRAM controller.

The ao486 project is currently only running on the Terasic DE2-115 board.

### Resource usage

The project is synthesised for the Altera Cyclone IV E EP4CE115F29C7 device.
Resource utilization is as follows:

| Unit               | Logic cells | M9K memory blocks |
|--------------------|-------------|-------------------|
| ao486 processor    | 36517       | 47                |
| floppy             | 1514        | 2                 |
| hdd                | 2071        | 17                |
| nios2              | 1056        | 3                 |
| onchip for nios2   | 0           | 32                |
| pc_dma             | 848         | 0                 |
| pic                | 388         | 0                 |
| pit                | 667         | 0                 |
| ps2                | 742         | 2                 |
| rtc                | 783         | 1                 |
| sound              | 37131       | 29                |
| vga                | 2534        | 260               |

The fitter raport after compiling all components of the ao486 project is as
follows:

```
Fitter Status : Successful - Sun Mar 30 21:00:13 2014
Quartus II 64-Bit Version : 13.1.0 Build 162 10/23/2013 SJ Web Edition
Revision Name : soc
Top-level Entity Name : soc
Family : Cyclone IV E
Device : EP4CE115F29C7
Timing Models : Final
Total logic elements : 91,256 / 114,480 ( 80 % )
    Total combinational functions : 86,811 / 114,480 ( 76 % )
    Dedicated logic registers : 26,746 / 114,480 ( 23 % )
Total registers : 26865
Total pins : 108 / 529 ( 20 % )
Total virtual pins : 0
Total memory bits : 2,993,408 / 3,981,312 ( 75 % )
Embedded Multiplier 9-bit elements : 44 / 532 ( 8 % )
Total PLLs : 1 / 4 ( 25 % )
```

The maximum frequency is 39 MHz. The project uses a 30 MHz clock.

### CPU benchmarks

The package DosTests.zip from
http://www.roylongbottom.org.uk/dhrystone%20results.htm
was used to benchmark the ao486.

| Test                               | Result        |
-------------------------------------|---------------|
| Dhryston 1 Benchmark Non-Optimised | 1.00 VAX MIPS |
| Dhryston 1 Benchmark Optimised     | 4.58 VAX MIPS |
| Dhryston 2 Benchmark Non-Optimised | 1.01 VAX MIPS | 
| Dhryston 2 Benchmark Optimised     | 3.84 VAX MIPS |


### Running software

The ao486 successfuly runs the following software:
- Microsoft MS-DOS version 6.22,
- Microsoft Windows for Workgroups 3.11,
- Microsoft Windows 95,
- Linux 3.13.1.

### BIOS

The ao486 project uses the BIOS from the Bochs project
(http://bochs.sourceforge.net, version 2.6.2). Some minor changes
were required to support the hard drive.

The VGA BIOS is from the VGABIOS project (http://www.nongnu.org/vgabios,
version 0.7a). No changes were required. The VGA model does not have VBE
extensions, so the extensions were disabled.

### NIOS2 controller

The ao486 SoC uses a Altera NIOS2 processor for managing all components and
displaying the contents of the On Screen Display.

The OSD allows the user to insert and remove floppy disks.

### License

All files in the following directories:
- rtl,
- ao486_tool,
- sim

are licensed under the BSD license:

All files in the following directories:
- bochs486,
- bochsDevs

are taken from the Bochs Project and are licensed under the LGPL license.

The binary file sd/fd_1_44m/fdboot.img is taken from the FreeDOS project.

The binary file sd/bios/bochs_legacy is a compiled BIOS from the Bochs project.

The binary file sd/vgabios/vgabios-lgpl is a compiled VGA BIOS from the vgabios
project.

### Compiling
To compile the SoC, which contains the NIOS II microcontroller,  Altera Quartus II software is required.
The Verilog components of the SoC, in particular the ao486 processor, should be possible to compile
in any Verilog compiler. Currently synthesis project files are prepared only for Altera Quartus II.

NOTE: In the current version some synthesis project files -- especially the paths in those files, could be
broken.

#### ao486 processor
To compile the ao486 processor load the project file from syn/components/ao486/ao486.qpf.

#### SoC
To compile the ao486 SoC load the project file from syn/soc/soc.qpf.

Before compiling in Altera Quartus II, the Qsys system must be generated.

#### BIOS
To compile the BIOS do the following:
- extract the bochs-2.6.2 source archive,
- apply the patch from the directory bios/bochs-2.6.2 by running in the extracted directory:
  patch -p1 < (path to patch file)
- run ./configure in bochs
- run make in bochs
- cd bios
- make
- the binary file BIOS-bochs-legacy works with ao486 SoC.

#### VGABIOS
To compile the VGABIOS do the following:
- extract the vgabios-0.7a source archive,
- apply the patch form the directory bios/vgabios-0.7a by running in the extracted directory:
  patch -p1 < (path to patch file)
- run make in vgabios,
- the binary file VGABIOS-lgpl-latest.bin works with ao486 SoC.

### Running the SoC on Terasic DE2-115

- compile the soc Altera Quartus II project in syn/soc/soc.qpf
- compile the firmware for the NIOS II by:
    - opening the Nios II Software Build Tools for Eclipse,
    - creating a workspace in the directory syn/soc/firmware,
    - importing the two projects 'exe' and 'exe_bsp',
    - genrating BSP on the 'exe_bsp' project,
    - compiling the 'exe' project.
- compile the BIOS and copy the binary to the directory sd/bios,
- compile the VGABIOS and copy the binary to the directory sd/vgabios,
- compile the ao486_tool by running 'ant jar' in the directory ao486_tool,
- edit the files in the directory sd/hdd. They contain the position of the virtual hard disk located on
  the SD card. The start entry must be a multiplicity of 512. The values are in bytes from the begining
  of the SD card,
- run 'java -cp ./dist/ao486_tool.jar ao486.SDGenerator' in the directory ao486_tool,
- copy the file ao486_tool/sd.dat to the first sectors of the SD card by using 'dd if=sd.dat of=/dev/sdXXX'.
- insert the SD card to the Terasic DE2-115 board,
- program the FPGA using the SOF file,
- load and run the firmware of the NIOS II controller,
- select the BIOS file on the On Screen Display by using KEY0 for down, KEY1 for up and KEY2 for select,
- select the VGABIOS file on the OSD,
- select the hard drive on the OSD,
- select the floppy on the OSD. Use the KEYs to select the floppy image. Use KEY3 to cancel.
- after selecting the floppy or pressing cancel, ao486 boots,
- to activate the OSD press KEY2.
