#!/usr/bin/perl

=head1 NAME 

createSequence_web.pl

=head1 DESCRIPTION

Perl script to create an artificial sequence similar to the intergenic 
regions from the model selected. The models are described in parts:

  a) The composition background of kmer frequencies in fixed windows.
  b) The repeats parsed from the alignments described by RepeatMasker, 
consensus bases acording to RepBase and Simple Repeats from TRF output.
  c) Transitional GC frecuencies in fixed windows.

To create the new sequence, first this creates a new non-repetitive sequence,
then, the artificially evolved repeat elements are "bombarded" in random 
positions and random orientations.

=head1 USAGE

Usage: perl createSequence.pl -m MODEL -s SIZE -o OUFILE [PARAMETERS] 

Required parameters:

  -m --model       Model to use (like hg19, mm9, ... etc)
  -s --size        Size in bases, kb, Mb, Gb are accepted
  -o --out         Output files to create *.fasta and *.inserts  [fake]
    
Optional or automatic parameters:

  -w --window      Window size for base generation               [1000]
  -k --kmer        Seed size to use                              [   4]
  -g --mingc       Minimal GC content to use                     [   0]
  -c --maxgc       Maximal GC content to use                     [ 100]
  -r --repeat      Repetitive fraction [0-100]                   [auto]
  -l --lowcomplex  Low complexity seq fraction [0-100]           [auto]
  -d --dir         Directory with model                          [data]
  -t --type        Include only this type of repeats             [ all]
  -N --numseqs     Create N sequences                            [   1]

  --write_base     Write the sequence pre-repeats (*.base.fasta)
  --no_repeat      Don't insert repeats
  --no_simple      Don't insert simple repeats
  --no_mask        Don't lower-case repeats
  --align          Print evolved repeat alignments to consensus
  
  --repbase_file   RepBase file (EMBL format)
  --repeats_file   File with repeats information*
  --inserts_file   File with repeat inserts information* 
  --gct_file       File with GC transitions information*
  --kmer_file      File with k-mer information*

  -v --verbose     Verbose mode on
  -h --help        Print this screen
  
=head1 EXAMPLES

a) Basic usage  
   perl createSequence.pl -m hg19 -s 1Mb -o fake

b) Only include Alu sequences
   perl createSequence.pl -m hg19 -s 1Mb -o fake -t Alu

c) Change k-mer size to 6 and window size to 2kb
   perl createSequence.pl -m hg19 -s 1Mb -o fake -w 2000 -k 6

d) Just create a base sequence without repeats
   perl createSequence.pl -m hg19 -s 1Mb -o fake --write_base --no_repeat

=head1 AUTHOR

Juan Caballero, Institute for Systems Biology @ 2012

=head1 CONTACT

jcaballero@systemsbiology.org

=head1 LICENSE

This is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation, 
either version 3 of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful, but WITHOUT ANY 
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
code.  If not, see <http://www.gnu.org/licenses/>.

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use List::Util qw/shuffle/;
use Data::Dumper;
use FindBin;
use CGI::Pretty qw/:standard/;

## Global variables
my $seq          =          ''; # The sequence itself
my $model        =       undef; # Model to use
my $kmer         =           4; # kmer size to use
my $out          =      'fake'; # Filename to use
my $size         =       undef; # Final size of the sequence
my $win          =        1000; # Window size for sequence GC transition
my $type         =       undef; # Select only a few repeat classes
my $help         =       undef; # Variable to activate help
my $debug        =       undef; # Variable to activate verbose mode
my %model        =          (); # Hash to store model parameters
my %repeat       =          (); # Hash to store repeats info
my %simple       =          (); # Hash to store low complex seqs info
my %inserts      =          (); # Hash to store repeat inserts info
my @inserts      =          (); # Array to store the insert sequences data
my %gct          =          (); # Hash for GC transitions GC(n-1) -> GC(n)
my %elemk        =          (); # Hash for kmers probabilities
my %gc           =          (); # Hash for GC content probabilities
my @gc_bin       =          (); # Fixed GC in the new sequence
my @classgc      =          (); # Array for class GC
my %classgc      =          (); # Hash for class GC
my $dir          = "$FindBin::RealBin/../data"; # Path to models/RebBase directories
my %rep_seq      =          (); # Hash with consensus sequences from RepBase
my %repdens      =          (); # Repeat density values
my $mut_cyc      =          10; # Maximal number of trials for mutations
my $ins_cyc      =         100; # Maximal number of trials for insertions
my $wrbase       =       undef; # Write base sequence too
my $rep_frc      =           0; # Repeats fraction
my $sim_frc      =           0; # Low complexity fraction
my @dna          = qw/A C G T/; # DNA alphabet
my $no_repeat    =       undef; # No repeats flag
my $no_simple    =       undef; # No simple repeats flag
my $no_mask      =       undef; # No soft masking (lower-case) repeats
my $mingc        =       undef; # Minimal GC
my $maxgc        =       undef; # Maximal GC
my $nrep         =           0; # Number of repeats inserted
my $nsim         =           0; # Number of simple repeats inserted
my $gct_file     =       undef; # GC transitions file 
my $repeat_file  =       undef; # Repeat file
my $kmer_file    =       undef; # kmer file
my $repbase_file =       undef; # RepBase file
my $insert_file  =       undef; # Repeat insert file
my $doFrag       =           1; # Fragment repeats flag
my $numseqs      =           1; # Number of sequences to create
my $showAln      =       undef; # print evolved repeats alignment to consensus

# CSS definition
my $style    =<<__STYLE__
<style type="text/css">
    body  { color: navy; background: lightyellow }
    h1    { color: navy; }
    table { border: 2px solid grey; border-collapse: collapse }
    th    { text-align: center; font-weight: bold; border: 2px solid grey; padding: 5px }
    td    { text-align: left; border: 1px solid grey; padding: 5px }
</style>
__STYLE__
;

# GC classes creation
my @valid_gc  = (37, 39, 42, 45, 100);

# Web form specific values
my @models   = qw/hg19 ailMel1 bosTau4 equCab2 gasAcu1 mm9 oryLat2 susScr2 anoCar2 calJac3 ci2 felCat4 monDom5 oviAri1 rheMac2 canFam2 danRer7 fr2 loxAfr3 ornAna1 panTro3 rn4 tetNig2 apiMel2 cavPor3 dm3 galGal3 mm10 oryCun2 strPur2	xenTro2/;
my $compress = 'zip';
my $min_size = 1000;
my $max_size = 100000;
my @gc_web   = (0,10,20,30,40,50,60,70,80,90,100);
my $outdir   = "./tmp"; 

# HTML header
print header('text/html'); 
print "<html>\n<head>\n<title></title>\n$style\n</head>\n<body>";
print h2('Artificial Intergenic Sequence Generator'), hr();
print p('This is a simulator designed to produce a DNA sequence similar to the non-functional (intergenic) regions of a genome to be use in genomic analysis.');
print p('If you are planning to run a large scale simulations, please install a local version, the source code is available <a href="http://caballero.github.com/FakeSequence/">here </a>and the models <a href="models/">here.</a>');
print hr();

if (defined param('model')) {
    my $model   = param('model');
    my $size    = param('size');
    my $kmer    = param('kmer');
    my $win     = param('win');
    my $min_gc  = param('min_gc');
    my $max_gc  = param('max_gc');
    my $repfrac = param('repfrac');
    my $reptype = param('reptype');
    
    if ($size < $min_size or $size > $max_size) {
        print p(i("Please use a size between $min_size and $max_size bases"));
        createForm();
    }
    else {
        print p('Generating sequences, please wait ...');
        my $id  = int(rand(1e9));
        createNewSequence($id);
        system ("$compress $outdir/$id.zip $outdir/$id.*");
        system ("rm $outdir/$id.fasta $outdir/$id.inserts");
        print p("Your files are in <a href=\"$outdir/$id.zip\">$id.zip</a>"); 
    }
}
else {
    createForm();
}

# HTML footer
print p('Citation: Caballero J, Smit AF, Hood L, Glusman G. <a href="http://nar.oxfordjournals.org/content/early/2014/05/06/nar.gku356.abstract">Realistic artificial DNA sequences as negative controls for computational genomics.</a> <i>Nucl. Acids Res.</i> 2014 doi: 10.1093/nar/gku356');
print p('Contact: please use the <a href="https://github.com/caballero/FakeSequence/issues">GitHub form.</a>');
print p(i('Institute for Systems Biology (2012)'));
print end_html();



#### MAIN ####
sub createNewSequence {
    my $id = shift @_;
    # GC classes creation
    $mingc = $valid_gc[ 0] unless (defined $mingc);
    $maxgc = $valid_gc[-1] unless (defined $maxgc);
    foreach my $gc (@valid_gc) {
        if ($gc >= $mingc and $gc <= $maxgc) {
            push @classgc, $gc;
            $classgc{$gc} = 1;
        }
    }

    if (defined $type) {
        $type =~ s/,/|/g;
    }

    # Loading model parameters
    $gct_file     = "$dir/$model/$model.GCt.W$win.data"         if (! defined $gct_file);
    $kmer_file    = "$dir/$model/$model.kmer.K$kmer.W$win.data" if (! defined $kmer_file);
    $repeat_file  = "$dir/$model/$model.repeats.W$win.data"     if (! defined $repeat_file);
    $insert_file  = "$dir/$model/$model.inserts.W$win.data"     if (! defined $insert_file);
    $repbase_file = "$dir/RepBase/RepeatMaskerLib.embl"         if (! defined $repbase_file);

    warn "Generating a $size sequence with $model model, output in \"$outdir/$out.fasta\" and \"$outdir/$out.inserts\" \n" if (defined $debug);
    open FAS, ">$outdir/$out.fasta" or errorExit("cannot write $outdir/$out.fasta");
    open INS, ">$outdir/$out.inserts" or errorExit("cannot write $outdir/$out.inserts");
    if (defined $wrbase) {
        open  BSE, ">$outdir/$out.base.fasta" or errorExit("cannot open $outdir/$out.base.fasta");
    }

    # Checking the size (conversion of symbols)
    $size = checkSize($size);
    errorExit("$size isn't a number or < 1kb") unless ($size >= 1000);

    # Loading models
    warn "Reading GC transitions in $gct_file\n" if(defined $debug);
    loadGCt($gct_file);

    warn "Reading k-mers in $kmer_file\n" if(defined $debug);
    loadKmers($kmer_file);

    unless (defined $no_simple or defined $no_repeat) {
        warn "Reading repeat information from $repeat_file\n" if (defined $debug);
        loadRepeats($repeat_file);
    }

    unless (defined $no_repeat) {
        warn "Reading repeat consensi from $repbase_file\n" if (defined $debug);
        loadRepeatConsensus($repbase_file);

        warn "Reading repeat insertions from $insert_file\n" if (defined $debug);
        loadInserts($insert_file);
    }

    for (my $snum = 1; $snum <= $numseqs; $snum++) {
        # Generation of base sequence
        my $fgc    = newGC();
        my @fseeds = keys %{ $elemk{$fgc} };
        my $fseed  = $fseeds[int(rand @fseeds)];
        $seq       = createSeq($kmer, $fgc, $size, $win, $fseed);
        $seq       = checkSeqSize($size, $seq);
        warn "Base sequence generated ($size bases)\n" if(defined $debug);

        # Write base sequence (before repeat insertions)
        if (defined $wrbase) {
            my $bseq = formatFasta($seq);
            print BSE  ">artificial_sequence_$snum MODEL=$model KMER=$kmer WIN=$win LENGTH=$size\n$bseq";
        }
        next if (defined $no_repeat and defined $no_simple);
        # Adding new elements
        warn "Adding repeats elements\n" if (defined $debug);
        $seq = insertRepeat($seq)     unless (defined $no_repeat);
        $seq = insertLowComplex($seq) unless (defined $no_simple);
        print INS  "### ARTIFICIAL SEQUENCE $snum ###\n";
        print INS  "#INI\tEND\tNUM\tREPEAT\tREPEAT_EVOL\n";
        print INS  join "\n", @inserts;
        print INS  "\n";

        warn "Generated a sequence with ", length $seq, " bases\n" if(defined $debug);
        $seq   =  uc($seq) if (defined $no_mask);
        $seq   =~ s/bad/NNN/ig;
        # Printing output
        warn "Printing outputs\n" if(defined $debug);
        $seq     = checkSeqSize($size, $seq);
        my $fseq = formatFasta($seq);
        print FAS  ">artificial_sequence_$snum MODEL=$model KMER=$kmer WIN=$win LENGTH=$size\n$fseq";
	    @inserts = ();
    }
    close INS;
    close FAS;
    close BSE;
}

sub createForm {
    print start_form();
    print p('Model ', popup_menu(-name => 'model', -values => \@models, -default => 'hg19'));
    print p('Kmer ',  popup_menu(-name => 'kmer', -values => [4, 6, 8], -default => 4));
    print p('Window ',  popup_menu(-name => 'win', -values => [1000], -default => 1000));
    print p('Size ',  textfield(-name => 'size', -value => 10000, -size => 10), i(" number between $min_size - $max_size"));
    print p('Minimal G+C ', popup_menu(-name => 'min_gc', -values => \@gc_web, -default => 40));
    print p('Maximal G+C ', popup_menu(-name => 'max_gc', -values => \@gc_web, -default => 60));
    print p('Repetitive fraction ',  textfield(-name => 'repfrac', -value => 0.5, -size => 10), i(" number between 0.0 - 0.95"));
    print p('Repeat Type ', textfield(-name => 'reptype', -value => 'All', -size => 10), i(" like Alu, MIR, LINE, LTR, ..."));

    print br();
	print submit(-name => 'Create!');
	print end_form();
}


# errorExit => catch an error and dies
sub errorExit {
    my $mes = shift @_;
    print p("Fatal error: $mes\nAborting\n");
    exit 1;
}

# formatFasta => break a sequence in blocks (80 col/line default)
sub formatFasta {
    my $sseq  = shift @_;
    my $col   = shift @_;
    $col    ||= 80;
    my $fseq  = '';
    while ($sseq) {
        $fseq .= substr ($sseq, 0, $col);
        $fseq .= "\n";
        substr ($sseq, 0, $col) = '';
    }
    return $fseq;
}

# defineFH => check if the file is compressed (gzip/bzip2), Return the handler.
sub defineFH {
    my ($fo) = @_;
    my $fh   = $fo;
    $fh      = "gunzip  -c $fo | " if ($fo =~ m/gz$/);
    $fh      = "bunzip2 -c $fo | " if ($fo =~ m/bz2$/);
    return $fh;
}

# checkBases => verify a sequence, change unclassified bases
sub checkBases {
    my $cseq = shift @_;
    $cseq =  uc $cseq;
    $cseq =~ tr/U/T/;
    if($cseq =~ /[^ACGT]/) {
        my @cseq = split (//, $cseq);
        my @bases = ();
        for (my $i = 0; $i <= $#cseq; $i++) {
            if    ($cseq[$i] =~ /[ACGT]/) {                 next; }
            elsif ($cseq[$i] eq 'R')      { @bases =     qw/A G/; }
            elsif ($cseq[$i] eq 'Y')      { @bases =     qw/C T/; }
            elsif ($cseq[$i] eq 'M')      { @bases =     qw/C A/; }
            elsif ($cseq[$i] eq 'K')      { @bases =     qw/T G/; }
            elsif ($cseq[$i] eq 'W')      { @bases =     qw/T A/; }
            elsif ($cseq[$i] eq 'S')      { @bases =     qw/C G/; }
            elsif ($cseq[$i] eq 'B')      { @bases =   qw/C T G/; }
            elsif ($cseq[$i] eq 'D')      { @bases =   qw/A T G/; }
            elsif ($cseq[$i] eq 'H')      { @bases =   qw/A T C/; }
            elsif ($cseq[$i] eq 'V')      { @bases =   qw/A C G/; }
            else                          { @bases = qw/A C G T/; }
            $cseq[$i] = $bases[ int(rand(@bases)) ];
        }
        $cseq = join('', @cseq);
    }
    return $cseq;
}

# revcomp => return the reverse complementary chain
sub revcomp {
    my $seq =  shift @_;
    $seq    =~ tr/ACGTacgt/TGCAtgca/;
    return reverse $seq;
}

# checkSeqSize => verify the sequence length
sub checkSeqSize {
    my $size     = shift @_;
    my $seq      = shift @_;
    my $old_size = length $seq;
    if ($old_size > $size) {
        warn "Sequence too long, removing ", $old_size - $size, " bases\n" if (defined $debug);
        $seq = substr ($seq, 0, $size);
    }
    elsif ($old_size < $size) {
        my $add   = $size - $old_size;
        warn "Sequence too short, adding $add bases\n" if (defined $debug);
        my $pos   = int(rand($old_size - $add));
        my $patch = substr($seq, $pos, $add);
        $seq     .= $patch;
    }
    return $seq;
}


# checkSize => decode kb, Mb and Gb symbols
sub checkSize{
    my $size   = shift @_;
    my $factor = 1;
    if    ($size =~ m/k/i) { $factor =  1e3; }
    elsif ($size =~ m/m/i) { $factor =  1e6; }
    elsif ($size =~ m/g/i) { $factor =  1e9; }
    $size  =~ s/\D//g;
    $size *=  $factor;
    return $size;
}

# loadGCt => load the GC transitions values
sub loadGCt {
    my $file   = shift @_;
    my $fileh  = defineFH($file);
    my %gc_sum = ();
    open G, "$fileh" or errorExit("cannot open $file");
    while (<G>) {
        chomp;
        next if (m/#/);
        my($pre, $post, $p, $num) = split (/\t/, $_);
        $num++; # give a chance to zero values
        my ($a, $b) = split (/-/, $pre);
        $pre  = $b;
        ($a, $b) = split (/-/, $post);
        $post = $b;
        next unless($pre  >= $mingc and $pre  <= $maxgc);
        next unless($post >= $mingc and $post <= $maxgc);
        $gct{$pre}{$post} = $num;
        $gc_sum{$pre} += $num;
    }
    close G;
    # Adjust the probability of GC
    foreach my $pre (keys %gct) {
        foreach my $post (keys %{ $gct{$pre} }) {
            $gct{$pre}{$post} /= $gc_sum{$pre};
        }
    }
}

# loadKmers => load the kmers frequencies
sub loadKmers {
    my $file  = shift @_;
    my $gc    = undef; 
    my $tot   = 0;
    my $fileh = defineFH($file);
    open K, "$fileh" or errorExit("cannot open $fileh");
    while (<K>) {
        chomp;
        if (m/#GC=\d+-(\d+)/) {
            $gc = $1;
        }
        else {
            my ($b, $f, @r) = split (/\s+/, $_);
            my $v = pop @r;
            $elemk{$gc}{$b} = $f;
            $v++; # give a chance to zero values
            if (defined $classgc{$gc}) {
                $gc{$gc} += $v;
                $tot     += $v;
            }
        }
    }
    close K;
    # Adjust the probability of GC
    foreach $gc (keys %classgc) { 
        $gc{$gc} /= $tot; 
    }
}

# loadRepeatConsensus => read file of RepBase consensus
sub loadRepeatConsensus {
    my $file  = shift @_;
    my $fileh = defineFH($file);
    my ($rep, $alt, $seq);
    open R, "$fileh" or errorExit("Cannot open $fileh");
    while (<R>) {
        chomp;
        if (m/^ID\s+(.+?)\s+/) {
            $rep = $1;
            $rep =~ s/_\dend//;
            $alt = undef;
        }
        elsif (m/^DE\s+RepbaseID:\s+(.+)/) {
            $alt = $1;
        }
        elsif (m/^\s+(.+)\s+\d+$/) {
            $seq =  $1;
            $seq =~ s/\s//g;
            $rep_seq{$rep} .= checkBases($seq);
            if (defined $alt) {
                $rep_seq{$alt} .= checkBases($seq) unless ($rep eq $alt);
            }
        }
    }
    close R;
}

# loadRepeats => read the repeats info
sub loadRepeats {
    my $file  = shift @_;
    my $fileh = defineFH($file);
    my $gc    = undef;
    my $nsim  = 0;
    my $nrep  = 0;
    open R, "$fileh" or die "cannot open $file\n";
    while (<R>) {
        chomp;
        if (m/#GC=\d+-(\d+)/) {
            $gc = $1;
        }
        else {
            # rename some repeats mislabeled in RepBase
            s/\?//;
            s/-int//;
            s/^ALR\/Alpha/ALR/;
            s/^L1M4b/L1M4B/;
            if (defined $type) {
                next unless (m/$type/i);
            }
            if (defined $no_simple) {
                next if (m/SIMPLE/);
            }
            
            if (m/SIMPLE/) {
                push @{ $simple{$gc} }, $_;
                $nsim++;
            }
            else {                            
                push @{ $repeat{$gc} }, $_;
                $nrep++;
            }
        }
    }
    close R;
    warn "found: SIMPLE=$nsim REPEAT=$nrep\n" if (defined $debug);
}

# loadInserts => read the repeat inserts info
sub loadInserts {
    my $file = shift @_;
    my $fileh = defineFH($file);
    my $gc    = undef;
    open I, "$fileh" or die "cannot open $file\n";
    while (<I>) {
        chomp;
        if (m/#GC=\d+-(\d+)/) {
            $gc = $1;
        }
        else {
            # rename some repeats mislabeled in RepBase
            my ($rep1, $rep2, $frq) = split (/\t/, $_);
            $rep1 =~ s/\?//g;
            $rep1 =~ s/-int//g;
            $rep1 =~ s/^ALR\/Alpha/ALR/g;
            $rep1 =~ s/^L1M4b/L1M4B/g;
            $rep2 =~ s/\?//g;
            $rep2 =~ s/-int//g;
            $rep2 =~ s/^ALR\/Alpha/ALR/g;
            $rep2 =~ s/^L1M4b/L1M4B/g;
            if (defined $type) {
                next unless ($rep1 =~ m/$type/i and $rep2 =~ m/$type/i);
            }
            $inserts{$gc}{$rep1}{$rep2} = $frq;
        }
    }
    close I;
}

# selPosition => find where to put a change
sub selPosition {
    my $seq = shift @_;
    my $gc  = shift @_;
    my $len = length $seq;
    my @pos = randSel($len, int($len/2) + 1 );
    #my @pos = ();
    #my %dat = ();
    #my $num = 0;
    #for (my $i = 0; $i <= ((length $seq) - $kmer - 1); $i++) {
    #    my $seed = uc(substr($seq, $i, $kmer));
    #    if (defined $elemk{$gc}{$seed}) {
    #        $dat{$i} = $elemk{$gc}{$seed};
    #        $num++;
    #    }
    #}
    #if ($num < 2) {
    #    @pos = (0);
    #}
    #else {
    #    foreach my $pos (sort { $dat{$a} <=> $dat{$b} } keys %dat) {
    #         push (@pos, $pos);
    #    }
    #}
    return @pos;
}

# addDeletions => remove bases
sub addDeletions {
    my $seq  = shift @_;
    my $ndel = shift @_;
    my $gcl  = shift @_;
    my $eval = shift @_;
    my $aln  = shift @_;
    my $tdel = 0;
    my $skip = 0;
    my @pos  = selPosition($seq, $gcl);
    
    my ($con, $mat, $mut) = split (/\n/, $aln);
    while ($ndel > 0) {
        my $bite = 1;
        last unless(defined $pos[0]);
        my $pos  = shift @pos;
        next if ($pos < $kmer);
        next if ($pos >= (length $seq) - $kmer);
        my $pre  = substr($seq, $pos, $kmer - 1);
        my $old  = substr($seq, $pos, $kmer);
        my $new  = substr($seq, $pos + $kmer, 1);
        if ($eval < $mut_cyc) {
            next unless(defined $elemk{$gcl}{"$pre$new"} and defined $elemk{$gcl}{"$old"});
            next if($elemk{$gcl}{"$old"} >= $elemk{$gcl}{"$pre$new"} + 1e-15);
        }
        
        substr($seq, $pos, $bite) = 'D' x $bite;
        substr($mat, $pos, $bite) = 'd' x $bite;
        substr($mut, $pos, $bite) = '-' x $bite;
        $ndel -= $bite;
        $tdel++;
    }
    $skip = $ndel;
    $eval++;
    $aln = join "\n", $con, $mat, $mut;
    warn "  Added $tdel deletions ($skip skipped, GC=$gcl)\n" if(defined $debug);
    if ($skip > 0 and $eval < $mut_cyc) {
        $gcl = newGC();
        ($seq, $aln) = addDeletions($seq, $skip, $gcl, $eval, $aln);
    }
    
    $seq =~ s/D//g;
    return $seq, $aln;
}

# addInsertions => add bases
sub addInsertions {
    my $seq  = shift @_;
    my $nins = shift @_;
    my $gcl  = shift @_;
    my $aln  = shift @_;
    my $tins = 0;
    my ($con, $mat, $mut) = split (/\n/, $aln);
    my @pos  = selPosition($seq, $gcl);
    while ($nins > 0) {
        my $ins  = 1;
        last unless(defined $pos[0]);
        my $pos = shift @pos;
        next if($pos < $kmer);
        
        my $seed = substr($seq, $pos - $kmer + 1, $kmer - 1);
        my $post = substr($seq, $pos, 1);
        my $eed  = substr($seed, 1);
        my $dice = rand();
        my $n    = $dna[$#dna];
        my $p    =  0;
        unless (defined $elemk{$gcl}{"$seed$n"} and defined $elemk{$gcl}{"$eed$n$post"}) {
            warn "Bad seed ($seed) in $pos ($seq)\n" if (defined $debug);
            next;
        }
        else {
            foreach my $b (@dna) {
                my $q = $p + $elemk{$gcl}{"$seed$b"};
                $n    = $b if ($dice >= $p);
                last if($dice >= $p and $dice <= ($q + 1e-15));
                $p    = $q;
            }
            next unless($dice >= $elemk{$gcl}{"$eed$n$post"} + 1e-15);
        }
        my $old = substr($seq, $pos, 1);
        my $om  = substr($mat, $pos, 1);
        substr ($seq, $pos, 1) = "$old$n";
        substr ($con, $pos, 1) = "$old-";
        substr ($mat, $pos, 1) = $om . "n";
        substr ($mut, $pos, 1) = "$old$n";
        $nins -= $ins;
        $tins++;
    }
    $aln = join "\n", $con, $mat, $mut;
    warn "  Added $tins insertions, GC=$gcl\n" if(defined $debug);
    return $seq, $aln;    
}

# addTransitions => do transitions (A<=>G, T<=>C)
sub addTransitions {
    my $seq  = shift @_;
    my $nsit = shift @_;
    my $gcl  = shift @_;
    my $eval = shift @_;
    my $aln  = shift @_;
    my $tsit = 0;
    my $skip = 0;
    my ($con, $mat, $mut) = split (/\n/, $aln);
    my @pos  = selPosition($seq, $gcl);
    while ($nsit > 0) {
        last unless(defined $pos[0]);
        my $pos = shift @pos;
        next if ($pos < $kmer);
        my $pre  = substr($seq, $pos - $kmer, $kmer + 1);
        my $post = chop $pre;
        my $old  = chop $pre;
        my $new  = '';
        
        if    ($old eq 'A') { $new = 'G'; }
        elsif ($old eq 'T') { $new = 'C'; }
        elsif ($old eq 'G') { $new = 'A'; }
        elsif ($old eq 'C') { $new = 'T'; }
        else                { next;     }
        
        my $pre_old = "$pre$old";
        my $pre_new = "$pre$new";
        my $post_old = substr("$pre_old$post", 1);
        my $post_new = substr("$pre_new$post", 1);
        
        if ($eval < $mut_cyc) {
            next unless(defined $elemk{$gcl}{$pre_old}  and defined $elemk{$gcl}{$pre_new});
            next unless(defined $elemk{$gcl}{$post_old} and defined $elemk{$gcl}{$post_new});
            next if($elemk{$gcl}{$pre_old}  >= $elemk{$gcl}{ $pre_new} + 1e-15);
            next if($elemk{$gcl}{$post_old} >= $elemk{$gcl}{$post_new} + 1e-15);
        }
        
        substr($seq, $pos - 1 , 1) = $new;
        substr($mat, $pos - 1 , 1) = 'i';
        substr($mut, $pos - 1 , 1) = $new;
        $nsit--;
        $tsit++;
    }
    $skip = $nsit;
    $eval++;
    $aln = join "\n", $con, $mat, $mut;
    warn "  Added $tsit transitions ($skip skipped, GC=$gcl)\n" if(defined $debug);
    if ($skip > 0 and $eval < $mut_cyc) {
        $gcl = newGC();
        ($seq, $aln) = addTransitions($seq, $skip, $gcl, $eval, $aln);
    }
    return $seq, $aln;
}

# addTransversions => do transversions (A<=>T, C<=>G)
sub addTransversions {
    my $seq  = shift @_;
    my $nver = shift @_;
    my $gcl  = shift @_;
    my $eval = shift @_;
    my $aln  = shift @_;
    my $tver = 0;
    my $skip = 0;
    my ($con, $mat, $mut) = split (/\n/, $aln);
    my @pos  = selPosition($seq, $gcl);
    
    while ($nver > 0) {
        last unless(defined $pos[0]);
        my $pos = shift @pos;
        next if ($pos < $kmer);
        my $pre  = substr($seq, $pos - $kmer, $kmer + 1);
        my $post = chop $pre;
        my $old  = chop $pre;
        my $new  = '';
        
        if    ($old eq 'A') { $new = 'T'; }
        elsif ($old eq 'T') { $new = 'A'; }
        elsif ($old eq 'G') { $new = 'C'; }
        elsif ($old eq 'C') { $new = 'G'; }
        else                { next;       }
        
        my $pre_old = "$pre$old";
        my $pre_new = "$pre$new";
        my $post_old = substr("$pre_old$post", 1);
        my $post_new = substr("$pre_new$post", 1); 
        
        if ($eval < $mut_cyc) {
            next unless(defined $elemk{$gcl}{$pre_old}  and defined $elemk{$gcl}{$pre_new});
            next unless(defined $elemk{$gcl}{$post_old} and defined $elemk{$gcl}{$post_new});
            next if($elemk{$gcl}{$pre_old}  >= $elemk{$gcl}{ $pre_new} + 1e-15);
            next if($elemk{$gcl}{$post_old} >= $elemk{$gcl}{$post_new} + 1e-15);
        }

        substr($seq, $pos - 1, 1) = $new;
        substr($mat, $pos - 1, 1) = 'v';
        substr($mut, $pos - 1, 1) = $new;
        $nver--;
        $tver++;
    }
    $skip = $nver;
    $eval++;
    $aln = join "\n", $con, $mat, $mut;
    warn "  Added $tver transversions ($skip skipped, GC=$gcl)\n" if(defined $debug);
    if ($skip > 0  and $eval < $mut_cyc) {
        $gcl = newGC();
        ($seq, $aln) = addTransversions($seq, $skip, $gcl, $eval, $aln);
    }
    return $seq, $aln;
}

# calGC => calculate the GC content
sub calcGC {
    my $seq = shift @_;
    $seq =~ s/[^ACGTacgt]//g;
    my $tot = length $seq;
    my $ngc = $seq =~ tr/GCgc//;
    my $pgc  = int($ngc * 100 / $tot);
    
    # GCbins: 0-37 37-39 39-42 42-45 45-100
    my $new_gc = 39;
    if    ($pgc <  37) { $new_gc =  37; }
    elsif ($pgc <  39) { $new_gc =  39; }
    elsif ($pgc <  42) { $new_gc =  42; }
    elsif ($pgc <  45) { $new_gc =  45; }
    elsif ($pgc < 100) { $new_gc = 100; }
    
    return $new_gc;
}

# newGC => obtain a new GC based on probabilities
sub newGC {
    my $gc = $classgc[0];
    if ($#classgc > 1) {
        my $dice   = rand();
        my $p      = 0;
        foreach my $class (@classgc) {
            my $q = $p + $gc{$class};
            $gc   = $class if($dice >= $p);
            last if($dice >= $p and $dice <= $q);
            $p    = $q;
        }
    }
    return $gc;
}

# transGC => get a new GC change based on probabilities
sub transGC {
    my $old_gc = shift @_;
    my $new_gc = $old_gc;
    my $dice   = rand();
    my $p      = 0;
    foreach my $gc (keys %{ $gct{$old_gc} }) {
        my $q   = $p + $gct{$old_gc}{$gc};
        $new_gc = $gc if($dice >= $p);
        last if($dice >= $p and $dice <= $q);
        $p      = $q;
    }
    return $new_gc;
}

# createSeq => first step to create a new sequence (major loop)
sub createSeq {
    my $k     = shift @_;
    my $gc    = shift @_;
    my $len   = shift @_;
    my $win   = shift @_;
    my $seq   = shift @_;
    warn "creating new sequence\n" if (defined $debug);
    
    for (my $i = length $seq; $i <= $len + 100; $i += $win) {
        push @gc_bin, $gc;
        warn "    $i fragment, GC=$gc\n" if (defined $debug);
        my $seed   = substr($seq, 1 - $k);
        my $subseq = createSubSeq($k, $gc, $win - $k + 1, $seed);
        $seq      .= $subseq;
        $gc        = transGC($gc);
    }
    $seq = checkSeqSize($len, $seq);
    
    return $seq;
}

# createSeq => second step to create a new sequence (minor loop)
sub createSubSeq {
    my $k = shift @_;
    my $g = shift @_; 
    my $w = shift @_; 
    my $s = shift @_;

    # Extent to the window
    for (my $i = length $s; $i <= $w; $i++) {
        my $seed = substr ($s, 1 - $k);
        my $dice = rand();
        my $n    = $dna[$#dna];
        my $p    =  0;
        foreach my $b (@dna) {
            my $q = $p + $elemk{$g}{"$seed$b"};
            $n    = $b if ($dice >= $p);
            last if($dice >= $p and $dice <= $q);
            $p    = $q;
        }
        $s .= $n;
    }
    return $s;
}

# getRangeValue => obtain a random value in a range
sub getRangeValue {
    my ($min, $max) = @_;
    my $val = $min + int( rand ($max - $min) );
    return $val;
}

# insertRepeat => insert repeat elements
sub insertRepeat {
    warn "inserting repeat elements\n" if (defined $debug);
    my $s       = shift @_;
    my $urep    = 0;
    my $tot_try = 0; # to avoid infinite loops in dense repetitive regions
    
    # check if we already have repeats in sequence
    my $rbase  = $s =~ tr/acgt/acgt/;
    my $repfra = 100 * $rbase / length $s;
    
    # compute how much repeats we want
    unless (defined $rep_frc) {
        # select a random repetitive fraction
        $rep_frc = getRangeValue(10, 60);
    }
    my $repthr  = $rep_frc;
    warn "Trying to add $repthr\% in repeats\n" if (defined $debug);
    
    while ($repfra < $repthr) {
        $tot_try++;
        last if ($tot_try >= $ins_cyc);
        
        # select where we want to add a repeat
        my $pos  = int(rand ( (length $s) - 100));
        my $frag = substr ($s, $pos, 100); # at least 100 clean bases to try
        next if ($frag =~ m/[acgt]/);
        my $gc   = $gc_bin[int($pos/ $win)];
        next unless (defined $gc);
        next unless (defined $repeat{$gc}[0]); # at least one element
        
        # our bag of elements to insert
        my @ins = @{ $repeat{$gc} };
        my $ins = join "|", @ins;
        my $new = $ins[int(rand @ins)];
        my $seq = '';
        my $aln = '';
        warn "selected: $new\n" if (defined $debug);
        ($seq, $new, $aln) = evolveRepeat($new, $gc, 99999);
        next if ($seq eq 'BAD');
        $seq =~ s/BAD//g;
        next if ((length $seq) < 10);
        $seq = lc $seq;
        
        $frag = substr ($s, $pos, length $seq);
        next if ($frag =~ m/[acgt]/); # we've a repeat here, trying other position
        
        $urep++;
        substr($s, $pos, length $seq) = $seq;
		my $pos_end = $pos + length $seq;
		my ($con, $mat, $mut) = split (/\n/, $aln);
		my $old = $con;
		$old =~ s/-//g;
		my $inslen = length $old;
		$con = "CON $con";
		$mat = "    $mat";
		$mut = "NEW $mut";
		my $nsit = $mat =~ tr/i/i/;
        my $psit = sprintf("%.2f", 100 * $nsit / $inslen);
        my $nver = $mat =~ tr/v/v/;
        my $pver = sprintf("%.2f", 100 * $nver / $inslen);
        my $ndel = $mat =~ tr/d/d/;
        my $pdel = sprintf("%.2f", 100 * $ndel / $inslen);
        my $nins = $mat =~ tr/n/n/;
        my $pins = sprintf("%.2f", 100 * $nins / $inslen);
        my $info = "Transitions = $nsit ($psit\%), Transversions = $nver ($pver\%), Insertions = $nins ($pins\%), Deletions = $ndel ($pdel\%)"; 
        
        if (defined $showAln) { 
            push @inserts, "$pos\t$pos_end\t$urep\t$new\[$seq\]\t$info\n$con\n$mat\n$mut\n";
        }
        else {
            push @inserts, "$pos\t$pos_end\t$urep\t$new\[$seq\]\t$info";
        }
        $rbase   = $s =~ tr/acgt/acgt/;
        $repfra  = 100 * $rbase / length $s;
        $tot_try = 0;
    }
    warn "Inserted: $urep repeats, repetitive sequence = $repfra \%\n" if (defined $debug);
    return $s;
}

# insertLowComplex => insert low complexity/simple repeat elements
sub insertLowComplex {
    warn "inserting low complex elements\n" if (defined $debug);
    my $s       = shift @_;
    my $usim    = 0;
    my $tot_try = 0; # to avoid infinite loops in dense repetitive sequences
    
    # check if we already have repeats in sequence
    my $rbase  = $s =~ tr/acgt/acgt/;
    my $repfra = 100 * $rbase / length $s;
    
    # compute how much repeats we want
    unless (defined $sim_frc) {
        # select a random repetitive fraction
        $sim_frc = getRangeValue(0, 2);
    }
    my $repthr = $rep_frc + $sim_frc;
    $repthr = 99 if ($repthr > 99);
    warn "Trying to add $sim_frc\% of low complexity sequences\n" if (defined $debug);
    
    while ($repfra < $repthr) {
        $tot_try++;
        last if ($tot_try >= $ins_cyc);
        
        # select where we want to add a repeat
        my $pos  = int(rand ( (length $s) - 100));
        my $frag = substr ($s, $pos, 100); # at least 100 bases to try
        next if ($frag =~ m/[acgt]/);
        my $gc   = $gc_bin[int($pos/ $win)];
        next unless (defined $gc);
        next unless (defined $simple{$gc}[0]); # at least one element
        
        # our bag of elements to insert
        my @ins = @{ $simple{$gc} };
        my $new = $ins[int(rand @ins)];
        warn "selected: $new\n" if (defined $debug);
        my ($seq, $aln) = evolveSimple($new, $gc);
        next if ($seq eq 'BAD');
        $seq =~ s/BAD//g;
        $seq = lc $seq;
        next if ((length $seq) < 10);
        
        $frag = substr ($s, $pos, length $seq);
        next if ($frag =~ m/[acgt]/); # we've a repeat here, trying other position
        $usim++;
        substr($s, $pos, length $seq) = $seq;        
		my $pos_end = $pos + length $seq;
	    my ($con, $mat, $mut) = split (/\n/, $aln);
		my $old = $con; 
		$old =~ s/-//g;
		my $inslen = length $old;
		$con = "CON $con";
		$mat = "    $mat";
		$mut = "NEW $mut";
		my $nsit = $mat =~ tr/i/i/;
        my $psit = sprintf("%.2f", 100 * $nsit / $inslen);
        my $nver = $mat =~ tr/v/v/;
        my $pver = sprintf("%.2f", 100 * $nver / $inslen);
        my $ndel = $mat =~ tr/d/d/;
        my $pdel = sprintf("%.2f", 100 * $ndel / $inslen);
        my $nins = $mat =~ tr/n/n/;
        my $pins = sprintf("%.2f", 100 * $nins / $inslen);
        my $info = "Transitions = $nsit ($psit\%), Transversions = $nver ($pver\%), Insertions = $nins ($pins\%), Deletions = $ndel ($pdel\%)"; 

        if (defined $showAln) {
            push @inserts, "$pos\t$pos_end\t$usim\t$new\[$seq\]\t$info\n$con\n$mat\n$mut\n";
        }
        else {
            push @inserts, "$pos\t$pos_end\t$usim\t$new\[$seq\]\t$info";
        }
        $rbase   = $s =~ tr/acgt/acgt/;
        $repfra  = 100 * $rbase / length $s;
        $tot_try = 0;
    }
    warn "Inserted: $usim low complexity sequences, repetitive sequence = $repfra \%\n" if (defined $debug);
    return $s;
}

# evolveSimple => return the evolved repeat
sub evolveSimple {
    my $sim   = shift @_;
    my $gc    = shift @_;
    my $seq   = '';
    my ($lab, $seed, $dir, $exp, $div, $indel) = split (/:/, $sim);
    my ($min, $max);
    $dir = rand; # random direction
    
    # define values from ranges (if applicable)
    if ($exp =~ /-/) {
        ($min, $max) = split (/-/, $exp);
        $exp = getRangeValue($min, $max);
    }
    if ($div =~ /-/) {
        ($min, $max) = split (/-/, $div);
        $div = getRangeValue($min, $max);
    }
    if ($indel =~ /-/) {
        ($min, $max) = split (/-/, $indel);
        $indel = getRangeValue($min, $max);
    }
    
    # create the sequence
    $seq      = $seed x (int($exp) + 1);
    $seq      = revcomp($seq) if ($dir > 0.5);
    my $mat   = '|' x length $seq;
    my $aln   = join "\n", $seq, $mat, $seq;
    my $mut   = int($div * (length $seq) / 100);
    my $nsit  = int($mut / 2);
    my $nver  = $mut - $nsit;
    my $nid   = int($indel * (length $seq) / 100);
    my $ndel  = int(rand $nid);
    my $nins  = $nid - $ndel;
    ($seq, $aln) = addTransitions(  $seq, $nsit, $gc, 0, $aln) if($nsit > 0);
    ($seq, $aln) = addTransversions($seq, $nver, $gc, 0, $aln) if($nver > 0);
    ($seq, $aln) = addInsertions(   $seq, $nins, $gc,    $aln) if($nins > 0);
    ($seq, $aln) = addDeletions(    $seq, $ndel, $gc, 0, $aln) if($ndel > 0);
    return $seq, $aln;
}

# evolveRepeat => return the evolved repeat
sub evolveRepeat {
    my ($rep, $gc, $old_age) = @_;
    return ('BAD', $rep) unless ($rep =~ m/:/);

    my $seq   = '';
    my ($type, $fam, $dir, $div, $ins, $del, $frag, $break) = split (/:/, $rep);
    my ($mut, $nins, $ndel, $nsit, $nver, $cseq, $min, $max, $ini, $age, $aln, $mat);
    $dir = rand; # direction is random
    
    return ('BAD', $rep) unless (defined $type);
    
    unless (defined $rep_seq{$type}) {
        warn "sequence for $type ($fam) not found!\n" if (defined $debug);
        return ('BAD', $rep);
    }
    
    # get values from ranges (if applicable)
    if ($div =~ /-/) {
        ($min, $max) = split (/-/, $div);
        $div = getRangeValue($min, $max);
    }
    if ($ins =~ /-/) {
        ($min, $max) = split (/-/, $ins);
        $ins = getRangeValue($min, $max);
    }
    if ($del =~ /-/) {
        ($min, $max) = split (/-/, $del);
        $del = getRangeValue($min, $max);
    }
    if ($frag =~ /-/) {
        ($min, $max) = split (/-/, $frag);
        $frag = getRangeValue($min, $max);
        $frag = length $rep_seq{$type} if ($frag > length $rep_seq{$type});
    }
    if ($break =~ /-/) {
        ($min, $max) = split (/-/, $break);
        $break = getRangeValue($min, $max);
    }
    
    $age  = $div + $ins + $del + ($break * 10); # how old are you?
    return ('BAD', $rep) if ($age > $old_age);
    
    # ok, evolve the consensus sequence
    $ini  = int( rand( (length $rep_seq{$type}) - $frag));
    $seq  = substr ($rep_seq{$type}, $ini, $frag);
    $seq  = revcomp($seq) if ($dir > 0.5);
    $mat  = '|' x length $seq;
    $aln  = join "\n", $seq, $mat, $seq;
    $mut  = int($div * (length $seq) / 100);
    $nsit = int($mut / 2);
    $nver = $mut - $nsit;
    $nins = int($ins * (length $seq) / 100);
    $ndel = int($del * (length $seq) / 100);
    ($seq, $aln) = addTransitions(  $seq, $nsit, $gc, 0, $aln) if($nsit > 0);
    ($seq, $aln) = addTransversions($seq, $nver, $gc, 0, $aln) if($nver > 0);
    ($seq, $aln) = addInsertions(   $seq, $nins, $gc,    $aln) if($nins > 0);
    ($seq, $aln) = addDeletions(    $seq, $ndel, $gc, 0, $aln) if($ndel > 0);
    
    # split the repeat if required    
    if ($break > 1 and $age > 10 and $doFrag == 1) {
        my $num = 1;
        for (my $try = 0; $try <= $ins_cyc; $try++) {
            $num++;
            warn "generating insert: $gc, $type#$fam, $age\n" if (defined $debug);
            my ($insert, $repinfo, $insaln) = getInsert($gc, "$type#$fam", $age);
			if ($insert eq 'BAD' or (length $insert) < 1) {
				warn "   insert rejected\n" if (defined $debug);
				$num--;
				next;
			}
            my $target = int(rand(length $seq));
            my ($con, $mat, $mut) = split (/\n/, $aln);
            my ($inscon, $insmat, $insmut) = split (/\n/, $insaln);
            substr($seq, $target, 1) = $insert;
			substr($con, $target, 1) = $inscon;
			substr($mat, $target, 1) = $insmat;
			substr($mut, $target, 1) = $insmut;
			$aln  = join "\n", $con, $mat, $mut;
			$rep .= ",$repinfo\[$insert\]";
            
			last if ($num > $break);
        }
    }
    
    return ($seq, $rep, $aln);
}

# getInsert => select a new repeat to insert into another
sub getInsert {
    my ($gc, $rep, $age) = @_;
    my $new_rep = '';
    my $new_aln = '';
    my $seq     = 'BAD';
    my $tries   = 0;
    while (1) {
        $tries++;
        last if ($tries > $mut_cyc);
        my $dice = rand;
        my $p    = 0;
        my @rep  = keys %{ $inserts{$gc}{$rep} };
        last unless ($#rep > 0);
        foreach my $ins (@rep) {
            $new_rep = $ins;
            $p += $inserts{$gc}{$rep}{$ins};
            last if ($dice <= $p);
        }
        $new_rep =~ s/#/:/;
        # our bag of elements to insert
        my @rep_bag = ();
        foreach my $sel (@{ $repeat{$gc} }) {
            push @rep_bag, $sel if ($sel =~ m/^$new_rep:/);
        }
        last unless ($#rep_bag > 0);
        my @ins = shuffle(@rep_bag);
        my $new = $ins[int(rand @ins)];
        warn "insert: $new\n" if (defined $debug);
        my $new_age = $age - 20;
        $new_age    = 10 if ($new_age < 10);
        $new =~ s/\d+$/1/;
        ($seq, $new_rep, $new_aln) = evolveRepeat($new, $gc, $new_age);
        next if ($seq eq 'BAD');
        last;
    }
    return ($seq, $new_rep, $new_aln);
}

# randSel => select a random numbers in a finite range
sub randSel {
    my $total = shift @_;
    my $want  = shift @_;
    my %select = ();
    for (my $i = 0; $i <= $want; $i++) {
        my $num = int(rand $total);
        if (defined $select{$num}) {
            $i--;
        }
        else {
            $select{$num} = 1;
        }
    }
    return %select;
}

# THIS IS THE LAST LINE
