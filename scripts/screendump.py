#!/usr/bin/env python
"""
Reads c64u hex dump from stdin, decodes C64 screen codes (uppercase/graphics charset),
and prints a text rendering of the 40x25 screen to stdout.
"""
import sys, re

raw = sys.stdin.read()

# Parse hex bytes from c64u output: "0400: 13 09 04 ...  |...|"
hex_bytes = []
for line in raw.splitlines():
    if ':' in line and '|' in line:
        hex_part = line.split(':', 1)[1].split('|')[0]
        hex_bytes.extend(int(x, 16) for x in hex_part.split())

# C64 screen code → printable char (uppercase/graphics charset)
# Bit 7 = reverse video (same char, inverted colour) — strip it for text rendering
# $00      = @
# $01-$1A  = A-Z
# $1B      = [
# $1C      = (pound) → show as #
# $1D      = ]
# $1E      = ^ (up-arrow)
# $1F      = < (left-arrow)
# $20-$3F  = space ! " # $ % & ' ( ) * + , - . / 0-9 : ; < = > ?
# $40      = space (filled block → use space)
# $41-$5A  = reverse A-Z (same letters, inverted colour on real screen → uppercase here)
# $5B-$7F  = graphics chars → show as space
GRAPHICS = ' '

def sc_to_char(b):
    b = b & 0x7F          # strip reverse-video bit
    if b == 0x00: return '@'
    if 0x01 <= b <= 0x1A: return chr(ord('A') + b - 1)   # A-Z normal
    if b == 0x1B: return '['
    if b == 0x1C: return '#'
    if b == 0x1D: return ']'
    if b == 0x1E: return '^'
    if b == 0x1F: return '<'
    if 0x20 <= b <= 0x3F: return chr(b)                   # punctuation + digits
    if b == 0x40: return GRAPHICS
    if 0x41 <= b <= 0x5A: return chr(ord('A') + b - 0x41) # reverse A-Z → uppercase
    return GRAPHICS                                         # $5B-$7F graphics

if len(hex_bytes) < 1000:
    print("ERROR: only got {} bytes (need 1000)".format(len(hex_bytes)), file=sys.stderr)
    sys.exit(1)

print('+' + '-' * 40 + '+')
for row in range(25):
    line = ''.join(sc_to_char(hex_bytes[row * 40 + col]) for col in range(40))
    print('|' + line + '|')
print('+' + '-' * 40 + '+')
