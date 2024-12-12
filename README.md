# BBCZ80 for the Agon Light
This is a fork of BBCZ80 by R.T.Russell with a rewritten MOS layer for the Agon Light.

## BBCZ80
BBC BASIC (Z80) v5 is an implementation of the BBC BASIC programming language for the Z80 CPU.
It is largely compatible with Acorn's ARM BASIC V but with a few language extensions based on
features of 'BBC BASIC for Windows' and 'BBC BASIC for SDL 2.0'.  These extensions include the
EXIT statement, the address-of operator (^) and byte (unsigned 8-bit) variables and arrays
(& suffix character).

More details of the features added in version 5.00 can be found in the file WHATSNEW.TXT.

![Architecture](https://www.bbcbasic.co.uk/bbcbasic/z80arch.png)

The files in green constitute the generic BBC BASIC interpreter which is shared by all the
editions, it (just!) fits in 16 Kbytes so could be held in a ROM of this size.  The files in
the blue box are used to build the generic CP/M edition.  The files in the red box are used
to build the Acorn Z80 Second Processor edition.

Note that the name 'BBC BASIC' is used by permission of the British Broadcasting Corporation
and is not transferrable to a derived or forked work.

## Agon Light
The Agon Light version uses the following files from the original fork:

- ACORN.Z80
- ASMB.Z80
- DATA.Z80
- EVAL.Z80
- EXEC.Z80
- MAIN.Z80
- MATH.Z80

All Agon specific source code and ZDSII project files are in the folder src/zds.

### Building

The files from the original fork are converted to work with the ZDS assembler by the Python script tools/transform_source.py
and written out to the folder src/zds.

To build, load the project "BBC BASIC" into the Zilog ZDSII IDE and press F7.