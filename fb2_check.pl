#!/usr/bin/perl

use strict;
use warnings;
use utf8;

if ((scalar(@ARGV) < 1) || ($ARGV[0] eq '-h') || ($ARGV[0] eq '--help')) {
	print "Usage: $0 <fb2-file> [<output-file>] [-n]\n";
	print "    -n   Do not auto-increment output file index.\n";
	exit 1;
}

# Checks for quotation marks balance
# Input arguments:
#	$ln        - text line to be checked
#	$data      - arrayref where messages about disbalance should be added
#	$id        - text line identifier for future references
#	$id_suffix - [optional] supplemental identifier text to be appened at the end of the message
# Return value:
#	none
sub checkQuotes($$$;$) {
	my ($ln, $data, $id, $id_suffix) = @_;
	if (!$id_suffix) {
		$id_suffix = '';
	}
	else {
		$id_suffix = ": $id_suffix";
	}

	# Walk over quote characters and calculate numbers.
	# Negative number at any step means, closing quote appeared before opening.
	# Non-zero number at the end meand non-balanced quotes.
	$ln =~ s/[^«»“”]//g;
	my $qf = 0; # «French» quotes
	my $qe = 0; # “English” quotes
	for (my $i = 0; $i < length($ln); ++$i) {
		my $c = substr($ln, $i, 1);
		if ($c eq '«') {
			++$qf;
		}
		elsif ($c eq '»') {
			--$qf;
		}
		elsif ($c eq '“') {
			++$qe;
		}
		elsif ($c eq '”') {
			--$qe;
		}
		if ($qf < 0) {
			push @$data, "French closing quote before opening at $id";
		}
		if ($qe < 0) {
			push @$data, "English closing quote before opening at $id";
		}
	}
	if ($qf != 0) {
		my $msg;
		if ($qf > 0) {
			$msg = "-$qf";
		}
		else {
			$msg = "+" . abs($qf);
		}
		push @$data, "French at $id: $msg$id_suffix";
	}
	if ($qe != 0) {
		my $msg;
		if ($qe > 0) {
			$msg = "-$qe";
		}
		else {
			$msg = "+" . abs($qe);
		}
		push @$data, "English at $id: $msg$id_suffix";
	}
}

sub stripMarks($) {
	my ($str) = @_;
	$str =~ s/^[^0-9a-zа-яё]+//gi;
	$str =~ s/[^0-9a-zа-яё]+$//gi;
	return $str;
}

# List of test procedures
# Each test contains:
# 'enabled' - whether test should be run or not
# 'name'    - user-friendly name of the test
# 'analyze' - function that will be called for each line of the FB2 file;
#             input: 1) the test object itself, 2) the source line to be analyzed, 3) line number
# 'report'  - function that will be called after analyzing alal data
#             input: 1) the test object itself, 2) output handle
# Other fields may be specified and used internally (e.g. 'data' for gathering problems).
my @tests = (
	{
		# File encoding must be UTF-8.
		'enabled' => 1,
		'name' => 'Encoding',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			if ($ln =~ m/<\?xml .*encoding="([^\"]+)"/) {
				if (lc($1) ne 'utf-8') {
					push @{$this->{'data'}}, "Wrong encoding: '$1'. Expected 'utf-8'.";
				}
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# a) All links lead to existing targets.
		# b) Each target has at least one link leading to it (may contain false positives:
		#    orfan ID is not an error, but very suspicios situation).
		'enabled' => 1,
		'name' => 'Broken links / Orfan targets',
		'data' => { 'targets' => {}, 'links' => {} },
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			$this->{'data'}->{'targets'}->{$_} = 1 foreach ($ln =~ m/<[^<>]+ id="([^\"]+)"/g);
			$this->{'data'}->{'links'}->{$_} = 1 foreach ($ln =~ m/<(?:a|image) l:href="#([^\"]+)"/g);
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo "Broken links:\n";
			for my $elem (sort(keys(%{$this->{'data'}->{'links'}}))) {
				print $fo "\t$elem\n" if (!$this->{'data'}->{'targets'}->{$elem});
			}
			print $fo "Orfan targets:\n";
			for my $elem (sort(keys(%{$this->{'data'}->{'targets'}}))) {
				print $fo "\t$elem\n" if (!$this->{'data'}->{'links'}->{$elem});
			}
		}
	},
	{
		# Mismatched quotes in lines (may contain false positives when long quotation extends
		# over several paragraphs).
		'enabled' => 1,
		'name' => 'Quotes mismatch in lines',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			checkQuotes($ln, $this->{'data'}, "line $idx");
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# Mismatched quotes inside tags.
		'enabled' => 1,
		'name' => 'Quotes mismatch in tags',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			while ($ln =~ m/<([^<> ]+)( [^<>]*)?>([^<>]+)<\/\1>/g) {
				my ($tag, $params, $contents) = ($1, ($2 || ''), $3);
				my $contents_cut;
				if (length($contents) > 100) {
					$contents_cut = substr($contents, 0, 50) . '<...>' . substr($contents, -50);
				}
				else {
					$contents_cut = $contents;
				}
				checkQuotes($contents, $this->{'data'}, "line $idx", "<$tag$params>$contents_cut</$tag>");
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# There should be no space after closing italic/bold tag if it is at the end of phrase.
		'enabled' => 1,
		'name' => 'Spaces after italic/bold',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			my $num = ($ln =~ s/<\/(emphasis|strong)>\s([.,?!:;)&\]»”])/$&/g);
			if ($num) {
				push @{$this->{'data'}}, "At line $idx, number of entries: $num";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# There should be no space as first character in the link
		'enabled' => 1,
		'name' => 'Links starting with space',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			my $num = ($ln =~ s/<a [^<>]*>\s/$&/g);
			if ($num) {
				push @{$this->{'data'}}, "At line $idx, number of entries: $num";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# Comment should contain a backlink with the text identical to original link
		'enabled' => 1,
		'name' => 'Backlink contents',
		'data' => { 'backrefs' => {}, 'links' => {}, 'errors' => [] },
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			# Remember the current line ID
			my @ids = ($ln =~ m/<[^<>]+ id="([^\"]+)"/g);
			if (scalar(@ids) > 1) {
				push @{$this->{'data'}->{'errors'}}, "WARNING: Several IDs in one line $idx (" . join(', ', @ids) . "!";
			}
			my $id = $ids[0];
			if ($id) {
				if (!defined($this->{'data'}->{'backrefs'}->{$id})) {
					$this->{'data'}->{'backrefs'}->{$id} = [];
				}
				else {
					push @{$this->{'data'}->{'errors'}}, "WARNING: Several lines have identical ID '$id'!";
				}
			}

			# For each link we remember its contents and where it's located (to check back references)
			while ($ln =~ m/<a l:href="#([^\"]+)"[^<>]*>(.*?)<\/a>/g) {
				my ($href, $contents) = ($1, $2);
				$contents =~ s/<[^<>]*>//g;
				my %lnk = ( 'href' => $href, 'backref' => $id, 'contents' => $contents );
				if (!defined($this->{'data'}->{'links'}->{$href})) {
					$this->{'data'}->{'links'}->{$href} = [];
				}
				push @{$this->{'data'}->{'links'}->{$href}}, \%lnk;
				if ($id) {
					push @{$this->{'data'}->{'backrefs'}->{$id}}, \%lnk;
				}
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			# Dump already collected errors if any
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}->{'errors'}});

			# Checking that:
			# 1. each link has at least one corresponding backlink;
			# 2. if there is a backlink with text similar to the link's, it must be not similar but identical
			#    (similarity is checked by stripping punctuation from start/end).
			# Currently unused test (too many false positives):
			# x. there must be at least one backlink with text identical to that of the link.
			
			# %bugs collects problems of type No.2 in the following form:
			#   key = "href1|text1|href2|text2|..." - sorted list of all href IDs and text contents of the links participating in the problem (to exclude duplicates)
			#   value = [ $lnk1, $lnk2, ... ] - array of link objects for reporting
			my %bugs = ();

			# Enumerate all found unique link hrefs
			for my $href (sort keys %{$this->{'data'}->{'links'}}) {
				my $backrefs = $this->{'data'}->{'backrefs'}->{$href};
				my $lnks = $this->{'data'}->{'links'}->{$href};
				if (!$backrefs) {
					# No backrefs found - it's a broken link, cannot process it
					my $prefix = (scalar(@$lnks) > 1) ? 'texts' : 'text';
					print $fo "\tBroken link '" . $href . "' ($prefix: '" . join(', ', map { $_->{'contents'} } @$lnks) . "'), skipping.\n";
					next;
				}

				# Enumerate all links that lead to the currently selected href
				for my $lnk (@$lnks) {
					# Skip links that came from no-ID locations
					next if (!$lnk->{'backref'});
					# Search for possible backrefs
					my @found = ();
					for my $backref (@$backrefs) {
						if ($backref->{'href'} eq $lnk->{'backref'}) {
							push @found, $backref;
						}
					}

					# Process the found backrefs
					if (scalar(@found) == 0) {
						# No backrefs - report this immediately (block No.1)
						if (($lnk->{'contents'} ne '&lt;Заглавие&gt;') && ($lnk->{'contents'} ne 'примечание')) {
							print $fo "\tMissing expected backref '" . $lnk->{'backref'} . "' for link '" . $lnk->{'href'} . "' (text: '" . $lnk->{'contents'} . "')\n";
						}
					}
					else {
						# Now search for those backrefs that have contents different from the original link's only
						# by leading/trailing punctuation
						my $txt_found = 0; # Number of identical backrefs
						my @problems = (); # List of non-identical backrefs
						for my $backref (@found) {
							if (stripMarks($backref->{'contents'}) eq stripMarks($lnk->{'contents'})) {
								if ($backref->{'contents'} ne $lnk->{'contents'}) {
									push @problems, $backref;
								}
								else {
									++$txt_found;
								}
							}
						}

						if (scalar(@problems) > 0) {
							# Check that the problem list was not found earlier and prepare for output
							# First, add the original link to the list (it will be part of the report)
							@problems = sort { ($a->{'href'} cmp $b->{'href'}) || ($a->{'contents'} cmp $b->{'contents'}) } ($lnk, @problems);
							# Now, construct the unique key to identify this specific set of problematic backrefs
							my $key = '';
							my $val = [];
							for my $elem (@problems) {
								$key .= $elem->{'href'} . '|' . $elem->{'contents'} . '|';
								push @$val, $elem;
							}
							# Finally, check if the problem is already recorded, and if not, add it
							if (!$bugs{$key}) {
								$bugs{$key} = $val;
							}
						}
					}
				}
			}

			# Start printing block No.2
			print $fo "\n";
			for my $bugid (sort keys %bugs) {
				print $fo "\tPunctuation problem:\n";
				# Calculate maximum length among all href IDs from this problem (reverse-sort all lengths and take the first element)
				my $maxlen = (sort { $b <=> $a } map { length($_->{'href'}) } @{$bugs{$bugid}})[0] + 1;
				for my $elem (@{$bugs{$bugid}}) {
					printf $fo "\t\t%-" . $maxlen . "s '%s'\n", $elem->{'href'} . ':', $elem->{'contents'} . '</a>';
				}
			}
		}
	},
	{
		# Template for adding new tests
		'enabled' => 1,
		'name' => 'Joined words',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			return if (($ln =~ m/<binary /) .. ($ln =~ m/<\/binary>/));
			my $ln_text = ($ln =~ s/<[^<>]*>//gr);
			my @matches = grep { $_ !~ m/^(FictionBook|ДоУ|ЛитГаз|МолГв|УнС)$/ } ($ln_text =~ m/[a-zA-Zа-яёА-ЯЁ]*(?:[a-z][A-Z]|[а-яё][А-ЯЁ])[a-zA-Zа-яёА-ЯЁ]*/g);
			if (scalar(@matches) > 0) {
				push @{$this->{'data'}}, "Found at line $idx: " . join(' ', @matches);
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
	{
		# Template for adding new tests
		'enabled' => 0,
		'name' => 'Template',
		'data' => [],
		'analyze' => sub ($$$) {
			my ($this, $ln, $idx) = @_;
			if (0) {
				push @{$this->{'data'}}, "Error at line $idx";
			}
		},
		'report' => sub ($$) {
			my ($this, $fo) = @_;
			print $fo join('', map { "\t$_\n" } @{$this->{'data'}});
		}
	},
);

################################################################################
# Main code

my $fi;
my $fo;

# Open input/output files
open($fi, '<:encoding(UTF-8)', $ARGV[0]) or die "Failed to open input file '$ARGV[0]' for reading: $!";
if ($ARGV[1]) {
	my $fout = $ARGV[1];
	if ((!$ARGV[2] || ($ARGV[2] ne '-n')) && (-f $fout)) {
		my $fname;
		my $fext;
		if ($fout =~ m/^(.*)(\.[^.]+)$/) {
			($fname, $fext) = ($1, $2);
		}
		else {
			($fname, $fext) = ($fout, '');
		}
		my $idx = 0;
		do {
			++$idx;
			$fout = $fname . "-$idx" . $fext;
		} while (-f $fout);
		print "\nWARNING! File $ARGV[1] exists, writing output into $fout instead!\n";
	}
	open($fo, '>:encoding(UTF-8)', $fout) or die "Failed to open output file '$fout' for writing: $!";
	print $fo "\x{feff}";
}
else {
	$fo = \*STDOUT;
}

# Read the input file line-by-line and call all test analyzers for each line
my $idx = 0;
while (my $ln = <$fi>) {
	++$idx;
	for my $test (@tests) {
		next if (!$test->{'enabled'});
		$test->{'analyze'}->($test, $ln, $idx);
	}
}

# Now print collected test results
for my $test (@tests) {
	next if (!$test->{'enabled'});
	print $fo "Report from test '" . $test->{'name'} . "':\n";
	$test->{'report'}->($test, $fo);
	print $fo "\n";
}

# Close files and exit
close($fi);
close($fo) if ($fo != \*STDOUT);
