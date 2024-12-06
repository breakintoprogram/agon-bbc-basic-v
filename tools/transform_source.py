# Title:		Z80 Source Transformer
# Author:		Dean Belfield
# Created:		15/08/2024
# Last Updated:	06/12/2024
# Description:	Convert Z80 assembler to work on various assemblers
#
# Modinfo:
# 01/12/2024:	Improved the label parsing state machine
# 04/12/2024:	Exported files for ZDS now assemble
# 06/12/2024:	Added directives in hints and tweaked hints data

import sys
import os
import datetime
import re

# Global stuff
#
now = datetime.datetime.now()
registers = ["A", "B", "C", "D", "E", "H", "L", "IXL", "IXH", "IYL", "IYH", "AF", "BC", "DE", "HL", "IX", "IY", "SP", "PC"]
reservedWords = {
	"zds": ["AND", "OR", "MOD", "DIV", "IF", "ADDR", "COND", "CPL", "ERROR", "EVAL", "INT", "PAGE", "STRING", "TEXT", "VAR"],
	"sjasmplus": []
}

# Match a single regex
# 
def matchOne(regex, statement):
	l = re.search(regex, statement)
	if(l and len(l.groups()) > 0):
		return l.group(1)
	return None

# Get a label from the statement
#
def getLabel(statement):
	if(statement == None):
		return None
	m = matchOne(r"^(?:CALL|JR|JP)+\s+(?:C|NC|Z|NZ|M|P|PE|PO)+\s*,+\s*([a-zA-Z]+\w*)+", statement)
	if(m):
		return m	
	m = matchOne(r"^(?:DEFW|GLOBAL|EXTRN|CALL|CP|DJNZ|JR|JP|RST)+\s+([a-zA-Z]+\w*)+", statement)
	if(m):
		return m
	m = matchOne(r"^(?:LD|IN)+\s+(?:A|B|C|D|E|H|L|BC|DE|HL|IX|IY|SP)\s*,+\s*\(*([a-zA-Z]+\w*)+\)*", statement)
	if(m):
		return m
	return matchOne(r"^(?:LD|OUT)+\s+\(+([a-zA-Z]+\w*)+\)+\s*,+\s*(?:A|B|C|D|E|H|L|BC|DE|HL|IX|IY|SP)+", statement)

# Replace a string only if it is at the start of the string
# 
def replaceInstruction(string, find, replace):
	if(string.startswith(find)):
		return string.replace(find, replace, 1)
	return string 

# Replace a string on a word boundary provided it is not at the start 
#
def replaceOperator(string, find, replace):
	if(not string.startswith(find) and not f"'{find}'" in string):
		return re.sub(r"\b" + find + r"\b", replace, string)
	return string

# Represents a single line of source
# Members:
# - line: The original line
# - label: The label (if or ) 
#
class Line:
	def __init__(self, line):
		self.statement = None
		self.label = None
		self.comment = None
		self.statementLabel = None
		
		# Split the line into its component parts
		#
		state = 0
		for c in line.rstrip():

			if(state == 0): 					# Check if beginning of line is a label or not
				if(c == ";"):					# It is a comment?
					self.comment = c
					state = 4					# Go to the comment read state
				elif(c.isspace()):				# Is it a space?
					state = 2					# Go to the read statement state
				else:
					self.label = c
					state = 1					# It's a label, so go to the read label state

			elif(state == 1):					# Read a label in
				if(c == ":" or c.isspace()):	# Is it the end of the label?
					state = 2					# Yes, so go to the read statement state
				else:
					self.label += c

			elif(state == 2):					# Read the statement in - first skip whitespace
				if(not c.isspace()):
					self.statement = c
					state = 3

			elif(state  == 3):					# Read the rest of the statement in
				self.statement += c

			elif(state == 4):					# Read the comment in
				self.comment += c

		# Now get the statement label
		#
		label = getLabel(self.statement)
		if(label != None):
			if(self.statement.startswith("GLOBAL") or self.statement.startswith("EXTRN") or not label.upper() in registers):		
				self.statementLabel = label

	# Do some line level refactoring
	#
	def refactor(self, target, indent, xdef):
		if(self.label and self.label in reservedWords[target]):
			self.label+="_"

		if(self.statementLabel and self.statementLabel in reservedWords[target]):
			self.statement = replaceOperator(self.statement, self.statementLabel, self.statementLabel + "_")

		if(target == "zds"):
			if(self.statement):
				self.statement = replaceInstruction(self.statement, "EXTRN", "XREF")
				self.statement = replaceInstruction(self.statement, "GLOBAL", "XDEF")
				self.statement = replaceInstruction(self.statement, "DEFS", "DS")
				self.statement = replaceInstruction(self.statement, "DEFW", "DW")
				self.statement = replaceInstruction(self.statement, "DEFB", "DB")
				self.statement = replaceInstruction(self.statement, "DEFM", "DB")
				self.statement = replaceOperator(self.statement, "AND", "&")
				self.statement = replaceOperator(self.statement, "OR", "|")
				#
				# TODO: This is a bit of a bodge, needs improving
				# Replace escaped apostrophes ('') in the middle of strings
				#
				aposCount = self.statement.count("'")
				if(aposCount > 2 and aposCount%2 == 0):
					self.statement = self.statement.replace("''", "'", 1)

		elif(target == "sjasmplus"):
			if(self.statement):
				if(self.statement.startswith("EXTRN") or self.statement.startswith("GLOBAL")):
					self.comment = f";\t{self.statement}"
					self.statement = None
				else:
					if(self.label and self.label in xdef):
						self.label = f"@{self.label}"

		if(self.label == None and self.statement == None):
			return f"{self.comment or ''}"
		else:
			if(self.label):
				return f"{(self.label + ':').ljust(indent)}{self.statement or ''}\t{self.comment or ''}"
			else:
				return f"{''.ljust(indent)}{self.statement}\t{self.comment or ''}"
	
# The source file class
# Parameters:
# - filename: The filename of the source file
#
class Source:
	def __init__(self, filename):
		self.filename = filename
		self.module = os.path.splitext(os.path.basename(filename))[0]
		self.lines = []
		self.xdef = set()
		self.xref = set()
		self.target = None
		self.indent = None
		self.hints = {}
	
	# Set the target
	# - target: zds or sjasmplus
	#
	def setTarget(self, target):
		self.target = target

	# Set the indent
	# - indent: number of spaces to pad labels out to
	#	
	def setIndent(self, indent):
		self.indent = indent

	# Set source hints
	# - hints: Dictionary of manual fixes
	#
	def setHints(self, hints):
		self.hints = hints	

	# Add a comment
	# - comment: the comment to add (must be prefixed with ';')
	#
	def insertLine(self, comment):
		self.lines.append(Line(comment))

	# Open the file for reading
	#
	def open(self):
		full_path = os.path.expanduser(self.filename)
		self.file = open(full_path, "r")

	# Read and process the file
	# - ignoreFirstLine: set to true to ignore the first line
	# 
	def read(self, ignoreFirstLine):
		insert = not ignoreFirstLine
		while(True):
			line = self.file.readline()
			if(not line):
				break
			if(insert):
				self.lines.append(Line(line))
			insert = True

	# Close the file for reading
	#
	def close(self):
		self.file.close()

	# Do any source level refactoring
	#
	def refactor(self):
		output = []

		# Add the generic autogeneration comment
		# 
		output.append(Line(f";"))
		output.append(Line(f";Automatically created from original source on {now.strftime('%Y-%m-%d %H:%M:%S')}"))
		output.append(Line(f";"))

		if(self.target == "sjasmplus"):
			output.append(Line(f"\tMODULE {self.module}"))
		elif(self.target == "zds"):
			output.append(Line(f"\t.ASSUME ADL = 0"))

		# Source specific directives
		#
		if("directives" in self.hints[self.target]):
			for item in self.hints[self.target]["directives"]:
				output.append(Line(item))

		# Build up the xref and xdef lists
		#
		for line in self.lines:
			if(line.statement):
				#
				# xref labels are referenced in this module and are external
				#
				if(line.statement.startswith("EXTRN")): self.xref.add(line.statementLabel)
				#
				# xdef labels are exported from this module and referenced elsewhere
				#
				if(line.statement.startswith("GLOBAL")): self.xdef.add(line.statementLabel)
				#
				# Source specific hints
				#
				if(self.target in self.hints):
					if("hints" in self.hints[self.target]):
						for item in self.hints[self.target]["hints"]:
							if(item["hint"] in line.statement):
								if("prepend" in item):
									for p in item["prepend"]:
										output.append(Line(p))
								if("update" in item):
									line = Line(item["update"])

			output.append(line)

		# Add the module directives for sjasmplus
		#
		if(self.target == "sjasmplus"):
			output.append(Line(f"\tENDMODULE"))
		
		self.lines = output[:]

	# Export the source
	#
	def export(self):
		filename = os.path.basename(self.filename)
		if(self.target == "zds"):
			filename = filename.replace(".Z80", ".ASM").lower()
		dirname = os.path.join(os.path.dirname(self.filename), self.target)
		if(not os.path.exists(dirname)):
			os.makedirs(dirname)
		file = open(os.path.join(dirname, filename), "w")
		for line in self.lines:
			output = line.refactor(self.target, self.indent, self.xdef)
			if(output):
				file.write(f"{output}\n")
		file.close()

# The project class
#
class Project:
	def	__init__(self):
		self.filenames = []
		self.ignoreFirstLine = False
		self.source = []
		self.indent = 8
		self.hints = {}

	# Set the array of filenames to import
	# - filenames: array of paths to filenames
	#
	def setFilenames(self, filenames):
		self.filenames = filenames

	# Ignore the first line of the source code
	# - ignoreFirstLine: set to true to ignore
	#
	def setIgnoreFirstLine(self, ignoreFirstLine):
		self.ignoreFirstLine = ignoreFirstLine

	# Set the target
	# - target: zds or sjasmplus
	#
	def setTarget(self, target):
		if(target not in ["sjasmplus", "zds"]):
			raise Exception(f"Invalid target {target}")
		self.target = target
		print(f"Set target to {target}")

	# Set the indent
	# - indent: number of spaces to pad labels out to
	#
	def setIndent(self, indent):
		self.indent = indent

	# Set source hints
	# - hints: Dictionary of manual fixes
	#
	def setHints(self, hints):
		self.hints = hints
	
	# Parse the project 
	#
	def parse(self):
		for filename in self.filenames:
			print(f"Loading {filename}")
			s = Source(filename)
			s.setTarget(self.target)
			s.setIndent(self.indent)
			if(filename in self.hints):
				s.setHints(self.hints[filename])
			s.open()
			s.read(self.ignoreFirstLine)
			s.close()
			s.refactor()
			self.source.append(s)

	# Export the project
	#
	def export(self):
		for s in self.source:
			# Get list of labels in all the other sources that reference this - so this can export those labels
			#
			s.export()

# Start here
#
os.chdir(os.path.dirname(os.path.abspath(__file__)))

project = Project()
project.setIgnoreFirstLine(True)
project.setTarget("zds")
project.setIndent(16)
project.setFilenames([
	"../src/ACORN.Z80",
	"../src/ASMB.Z80",
	"../src/DATA.Z80",
	"../src/EVAL.Z80",	
	"../src/EXEC.Z80",
	"../src/MAIN.Z80",
	"../src/MATH.Z80",
])
project.setHints({
	"../src/ACORN.Z80": {
		"zds": {
			"directives": [ "\tSEGMENT CODE" ],
			"hints": [
				{
					"hint": "EQU\t0FFEEH",
					"update": "\tXREF\tOSWRCH"
				},
				{
					"hint": "EQU\t0FFF1H",
					"update": "\tXREF\tOSWORD"
				},
				{
					"hint": "EQU\t0FFF4H",
					"update": "\tXREF\tOSBYTE"
				}
			]
		}
	},
	"../src/ASMB.Z80": {
		"zds": {
			"directives": [ "\tSEGMENT CODE" ],
		}
	},
	"../src/DATA.Z80": {
		"zds": {
			"directives": [
				"\tDEFINE LORAM, SPACE = ROM",
				"\tSEGMENT LORAM",
				"\tALIGN 256",
				";",
				"\tXDEF\tKEYDOWN",
				"\tXDEF\tKEYASCII",
				"\tXDEF\tKEYCOUNT",
				"\tXDEF\tSCRAP"
			],
			"hints": [
				{
					"hint": "END",
					"prepend": [
						"KEYDOWN:\tDS\t1",
						"KEYASCII:\tDS\t1",
						"KEYCOUNT:\tDS\t1",
						"SCRAP:\tDS\t31",
						";",
						"\tALIGN 256",
						";"
					]
				}
			]
		}
	},
	"../src/EVAL.Z80": {
		"zds": {
			"directives": [
				"\tSEGMENT CODE",
				";",				
				"\tXDEF\tCOUNT0",
				"\tXDEF\tCOUNT1"
			],
			"hints": [
				{
					"hint": "FUNTOK+($-FUNTBL)/2",
					"prepend": [
						"FUNTBL_END:\tEQU\t$"
					],
					"update": "TCMD:\tEQU\tFUNTOK+(FUNTBL_END-FUNTBL)/2"
				}
			]
		}
	},
	"../src/EXEC.Z80": {
		"zds": {
			"directives": [ "\tSEGMENT CODE" ],
			"hints": [
				{
					"hint": "TCMD-128+($-CMDTAB)/2",
					"prepend": [
						"CMDTAB_END:\tEQU\t$"
					],
					"update": "TLAST:\tEQU\tTCMD-128+(CMDTAB_END-CMDTAB)/2"
				}
			]
		}
	},	
	"../src/MAIN.Z80": { 
		"zds": {
			"directives": [ "\tSEGMENT CODE" ],
			"hints": [
				{
					"hint": "\'Can\'\'t match \'",
					"update": "\tDB\t\"Can\'t match \""
				}
			]
		}
	},
	"../src/MATH.Z80": {
		"zds": {
			"directives": [ "\tSEGMENT CODE" ],
		}
	}	
})
project.parse()
project.export()