package Parse::GutenbergRoget;

use warnings;
use strict;

use Text::CSV_XS;

use base qw(Exporter);
our @EXPORT = qw(parse_roget);

=head1 NAME

Parse::GutenbergRoget - parse Project Gutenberg's Roget's Thesaurus

=head1 VERSION

version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

 use Parse::GutenbergRoget

 my %section = parse_roget("./roget15a.txt");

 print $section{1}[0][0]{text}; # existence

=head1 DESCRIPTION

A Roget's Thesaurus is more than the simple synonym/antonym finder included in
many dictionary sets.  It organizes words into semantically realted categories,
so that words with related meanings can be found in proximity to one another,
with the level of proximity indicating the level of similarity.

Project Gutenberg has produced an etext of the 1911 edition of Roget's
Thesaurus, and later began to revise it, in 1991.  While it's not the best
Roget-style thesaurus available, it's the best public domain electronic
thesaurus datasource I've found.

This module parses the file's contents into a Perl data structure, which can
then be stored in systems for searching and browsing it.  This module does
I<not> implement those systems.

The code is not complete.  This means that everything that can be parsed is not
yet being parsed.  It's important to realize that not everything is going to be
parseable.  There are too many typos and broken rules which, due to the lousy
nature of the rules, create ambiguity.  For a description of these rules see
L</"RULES"> below.

=head1 FUNCTIONS

=head2 C<< parse_roget($filename) >>

This function, exported by default, will attempt to open, read, and parse the
named file as a Project Gutenberg Roget's Thesaurus.  It has only been tested
with C<roget15a.txt>, which is not included in the distribution, because it's
too big.

It returns a hash with the following structure:

 %section = (
   ...
   '100a' => {
     major => 100, # major and minor form section identity
     minor => 'a',
     name  => 'Fraction',
     comments    => [ 'Less than one' ],
     subsections => [
       {
         type   => 'N', # these entries are nouns
         groups => [
           { entries => [
             { text => 'fraction' },
             { text => 'fractional part' }
           ] },
           { entries => [ { text => 'part &c. 51' } ] }
         ]
       },
       {
         type   => 'Adj',
         groups => [ { entries => [ ... ] } ]
       }
     ]
   }
   ...
 );

This structure isn't pretty or perfect, and is subject to change.  All of its
elements are shown here, except for one exception, which is the next likely
subject for change: flags.  Entries may have flags, in addition to text, which 
note things like "French" or "archaic."  Entries (or possibly groups) will also
gain cross reference attribues, replacing the ugly "&c. XX" text.  I'd also
like to deal with references to other subsections, which come in the form "&c.
Adj."  There isn't any reason for these to be needed, I think.

=cut

sub parse_roget {
  my ($filename) = @_;
  my %section = parse_sections($filename);
	bloom_sections(\%section);
	return %section;
}

=head2 C<< parse_sections($filename) >>

This function is used internally by C<parse_roget> to read the named file,
returning the above structure, parsed only to the section level.

=cut

sub parse_sections {
	my ($filename) = @_;

	open my $roget, '<', $filename
		or die "couldn't open $filename: $!";

	my $previous_section;
	my %section;

	my $peeked_line;
	my ($in_newheader, $in_longcomment);

	while (my $line = ($peeked_line || <$roget>)) {
		undef $peeked_line;

		chomp $line;
		next unless $line;
		next if ($line =~ /^#/); # comment

		if ($line =~ /^<--/) { $in_longcomment = 1; }
		if ($line =~ /-->$/) { $in_longcomment = 0; next; }
		next if $in_longcomment;

		if ($line =~ /^%/) {
			$in_newheader = not $in_newheader;
			next;
		}
		next if $in_newheader;

		$line =~ s/^\s+//;

		until ($peeked_line) {
			$peeked_line = <$roget>;
			last unless defined $peeked_line;
			chomp $peeked_line;
			if ($peeked_line and $peeked_line !~ /^\s{4}/
				and $peeked_line !~ /^(?:#|%|<--)/)
			{
				$line .= " $peeked_line";
				undef $peeked_line;
				if ($line =~ /[^,]+,[^.]+\.\s{4}/) {
					($line, $peeked_line) = split /\s{4}/, $line, 2;
				}
			}
		}

		my ($sec, $title, $newline) =
			($line =~ /^#?(\d+[a-z]?). (.*?)(?:--(.*))?$/);
		$line = ($newline||'') if ($sec);

		if ($sec) {
			(my($comment_beginning), $title, my($comment_end)) =
				($title =~ /(?:\[(.+?)\.?\])?\s*([^.]+)\.?\s*(?:\[(.+?)\.?\])?/);
			$title =~ s/\s{2,}//g;
			$section{$sec} = {
				name        => $title,
				subsections => [ { text => $line||'' } ],
				comments    => [ grep { defined $_ } ($comment_beginning, $comment_end) ]
			};
			@{$section{$sec}}{qw[major minor]} = ($sec =~ /^(\d+)(.*)$/);
			die "$sec" unless $section{$sec}{major};
			$previous_section = $sec;
		} else {
			$section{$previous_section}{subsections} ||= [];
			push @{$section{$previous_section}{subsections}}, { text => $line };
		}
	}
	return %section;

}

=head2 C<< bloom_sections(\%sections) >>

Given a reference to the section hash, this subroutine expands the sections
into subsections, groups, and entries.

=cut

sub bloom_sections {
	my ($section) = @_;

	my $decomma = Text::CSV_XS->new;
	my $desemi  = Text::CSV_XS->new({sep_char => ';'});

	my $types = qr/(Adj|Adv|Int|N|Phr|Pron|V)/;

	for (values %$section) {
		my $previous_subsection;
		for my $subsection (@{$_->{subsections}}) {
			$subsection->{text} =~ s/\.$//;
			$subsection->{text} =~ s/ {2,}/ /g;
			$subsection->{text} =~ s/(^\s+|\s+$)//;

			if (my ($type) = ($subsection->{text} =~ /^$types\./)) {
				$subsection->{text} =~ s/^$type\.//;
				$subsection->{type} = $type;
			} elsif ($previous_subsection) {
				$subsection->{type} = $previous_subsection->{type};
			} else {
				$subsection->{type} = 'UNKNOWN';
			}

			$desemi->parse($subsection->{text});
			$subsection->{groups} = [ map { { text => $_ } } $desemi->fields ];

			for my $group (@{$subsection->{groups}}) {
				$decomma->parse($group->{text});
				$group->{entries} = [ map { { text => $_, flags => [] } } $decomma->fields ];

				for (@{$group->{entries}}) {
					$_->{text}||= 'UNPARSED';
					if ($_->{text} =~ s/\[obs3\]//) {
						push @{$_->{flags}}, 'archaic? (1991)';
					}
					if ($_->{text} =~ s/|!//) {
						push @{$_->{flags}}, 'obsolete (1991)';
					}
					if ($_->{text} =~ s/|//) {
						push @{$_->{flags}}, 'obsolete (1911)';
					}
					$_->{text} =~ s/(^\s+|\s+$)//;
				}
			}
			$previous_subsection = $subsection;
		}
	}
}

=head1 THE FILE

A description of the source file's format, or lack thereof, will go here.

=head1 TODO

Well, a good first step would be a TODO section, and the THE FILE section,
above.

I'll write some tests that will only run if you put a C<roget15a.txt> file in
the right place.  I'll also try the tests with previous revisions of the file.

I'm also tempted to produce newer revisions on my own, after I contact the
address listed in the file.  The changes would just be to eliminate anomalies
that prevent parsing.  Distraction by shiny objects may prevent this goal.

The flags and cross reference bits above will be implemented.

The need for Text::CSV_XS may be eliminated.

Entries with internal quoting (especially common in phrases) will no longer
become UNPARSED.

I'll try to eliminate more UNKNOWN subsection types.

=head1 AUTHOR

Ricardo Signes, C<< <rjbs@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-parse-roget-pg@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically be
notified of progress on your bug as I make changes.

=head1 COPYRIGHT

Copyright 2004 Ricardo Signes, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
