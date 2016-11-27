#!/usr/bin/perl

use strict;
use warnings;
use utf8;

if ((scalar(@ARGV) < 1) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <fb2-file> [<output-file>]\n";
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
			$ln =~ s!(<\?xml.*encoding=")[^\"]+(".*\?>)!$1utf-8$2!;
			return $ln;
		}
	},
	{
		# Add backrefs from footnotes
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			$ln =~ s!_ftn(\d+)\">\s*\[(\d+)\]\s*!_ftn$1\"><a l:href="\x23_ftnref$2"><sup>$2</sup></a> !g;
			return $ln;
		}
	},
	{
		# Add links to footnotes
		'enabled' => 1,
		'func' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			$ln =~ s!_ftnref(\d+)\">(.*?)\s*\[(\d+)\]\s*!_ftnref$1\">$2<a l:href="#_ftn$3"><sup>$3</sup></a>!g;
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
my $fout = $ARGV[1] || $ARGV[0];
open($fo, '>:encoding(UTF-8)', $fout) or die "Failed to open output file '$fout' for writing: $!";

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
