#!/usr/bin/perl

use strict;
use warnings;
use utf8;

if ((scalar(@ARGV) < 1) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <fb2-file> <output-file>\n";
	exit 1;
}

# List of fixes
# Each fix contains:
# 'enabled' - whether fix should be applied or not
# 'analyze' - function that will be called for each line of the FB2 file;
#             input: 1) the fix object itself, 2) the source line, 3) line number;
#             output: fixed line
# Other fields may be specified and used internally (e.g. 'data' for gathering problems).
my @fixes = (
	{
		# Set encoding to UTF-8
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Replace encoding in the XML definition tag with utf-8.
			# (Actual file encoding is ensured by the :encoding(UTF-8) filter in open() call.)
			$ln =~ s!(<\?xml.*encoding=")[^\"]+(".*\?>)!$1utf-8$2!;
			return $ln;
		}
	},
	{
		# Remove AutBody_0 prefix
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Remove AutBody_0 prefix from IDs
			$ln =~ s!id=\"AutBody_0!id=\"!g;
			# Remove AutBody_0 prefix from link targets
			$ln =~ s!href=\"\x23AutBody_0!href=\"\x23!g;
			return $ln;
		}
	},
	{
		# Add backrefs from footnotes
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Search for an ID ending with _ftnNN followed by a footnote in form of [NN] (with or without spaces).
			# Remove the prefix from the ID, and replace the footnote with superscripted back-link and single space.
			$ln =~ s!id="[^\"]*_ftn(\d+)">\s*\[(\d+)\]\s*!id="_ftn$1"><a l:href="#_ftnref$2"><sup>$2</sup></a> !g;
			return $ln;
		}
	},
	{
		# Add links to footnotes
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Search for an ID ending with _ftnrefNN followed by some text and a footnote in form of [NN] (with or without spaces).
			# Remove the prefix from the ID, and replace the footnote with superscripted link.
			$ln =~ s!id="[^\"]*_ftnref(\d+)">(.*?)\s*\[(\d+)\]\s*!id="_ftnref$1">$2<a l:href="#_ftn$3"><sup>$3</sup></a>!g;
			return $ln;
		}
	},
	{
		# Fix letter titles
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Search for paragraphs that contain typical title for mail correspondence.
			# Replace <p> with <subtitle>, keeping all attributes.
			$ln =~ s!<p( [^<>]*|)>(.*((Аркадий и Борис|Аркадий|Борис)\s*—\s*.*?|—\s*(Аркадию|Борису)),.*?\s+19\d\d.*)</p>!<subtitle$1>$2</subtitle>!g;
			return $ln;
		}
	},
	{
		# 
		'enabled' => 0,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			return $ln;
		}
	},
);


################################################################################
# Main code

my $fi;
my $fo;

# Open input/output files
# First, check and fix the encoding
open($fi, '<', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
my $enc;
while (<$fi>) {
	if (m/<\?xml.*encoding="([^\"]+)"\s*\?>/) {
		$enc = $1;
		last;
	}
}
close($fi);
if (!$enc) {
	print "Could not determine source file encoding!\n";
	exit 1;
}

open($fi, '<:encoding(' . $enc . ')', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
open($fo, '>:encoding(UTF-8)', $ARGV[1]) or die "Failed to open output file '$ARGV[1]' for writing: $!";

# Read the input file line-by-line and apply fixes for each line
my $idx = 0;
while (my $ln = <$fi>) {
	++$idx;
	for my $fix (@fixes) {
		next if (!$fix->{'enabled'});
		$ln = $fix->{'func'}->($fix, $ln, $idx);
	}
	print $fo $ln;
}

# Close files and exit
close($fi);
close($fo);
