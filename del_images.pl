#!/usr/bin/perl

use strict;
use warnings;
use utf8;

if ((scalar(@ARGV) < 2) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <full-fb2-file> <output-file>\n";
	exit 1;
}

# Open input/output files
my $fi;
my $fo;
open($fi, '<:encoding(UTF-8)', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
open($fo, '>:encoding(UTF-8)', $ARGV[1]) or die "Failed to open input file '$ARGV[1]' for writing: $!";

my $inset_found = 0;
my $image_names_regex = '';
while (my $ln = <$fi>) {
	my $skip_line = 0;   # Whether to skip the current line or not
	if (($ln =~ m!<p>Вклейка</p>!) .. ($ln =~ m!</section>!)) {
		# We are inside the Inset section - skip all image references
		if ($ln =~ m!<image l:href="#([^\"]+)"\s*/>!) {
			$skip_line = 1;
			# Append the image file name to the regex
			if ($image_names_regex ne '') {
				$image_names_regex .= '|';
			}
			$image_names_regex .= quotemeta($1);
		}
	}
	if (($ln =~ m!<binary id="($image_names_regex)"[^<>]*>!) .. ($ln =~ m!</binary>!)) {
		# We are inside one of the images excluded earlier - skip all
		$skip_line = 1;
	}
	# Copy the input line into output if not skipped
	print $fo $ln if (!$skip_line);
}

close($fi);
close($fo);
