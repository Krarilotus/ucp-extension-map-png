"""Read-only inspection of native ranges used by Map PNG's bindings."""
import argparse
import capstone
import pefile

parser = argparse.ArgumentParser()
parser.add_argument('exe')
parser.add_argument('ranges', nargs='+', help='hex-address:hex-length')
args = parser.parse_args()
pe = pefile.PE(args.exe)
decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
for item in args.ranges:
    address, length = (int(part, 16) for part in item.split(':'))
    print('RANGE', hex(address))
    for instruction in decoder.disasm(pe.get_data(address - pe.OPTIONAL_HEADER.ImageBase, length), address):
        print(f'{instruction.address:08X} {instruction.bytes.hex(" "):32} {instruction.mnemonic} {instruction.op_str}')
