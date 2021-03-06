#!/usr/bin/perl

# neutrality test
# based on test-neutralite.bat by Vivien GUEANT @ https://lafibre.info
# written by Kirth Gersen under GNU GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html
# kgersen at hotmail dot com
# project home : https://github.com/kgersen/neutrality-test

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage; #TODO bug ?
use IPC::Open3;
use POSIX "strftime";
use POSIX ":sys_wait_h";
use IO::Handle;
use Config;

our $VERSION = 1.0.3;

=pod

=head1 NAME
  My::Module

=head1 SYNOPSIS
  neutrality-test
  test your ISP neutrality

=head1 DESCRIPTION
neutrality-test [options]
 Test your ISP neutrality
 Options:
   -debug           display debug informations
   -help            brief help message
   -4               IPv4 only
   -6               IPv6 only
   -csv             output results as a 'database ready' table
   -test "<test>"   performs the given test
   -size <size>     change size
   -ul              perform only upload tests
   -dl              perform only download tests
   -time <value>    timeout each test after <value> seconds
   -server <server> specify server (dns name or IP)

<test> format = "IP PORT PROTO EXT DIR"
  IP = 4 or 6
  PORT = a valid TCP port
  PROT = http or https
  EXT  = any file extention with a leading dot (ex: .zip)
  DIR  = GET or POST
<size> format = <value> or <value>/<value>
  <value> = <number> or <number>[KMGT]
  a single <value> set both upload & download size to the same value
  a double <value>/<value> set download (1st) and upload (2nd) distinct sizes
  K, M, G,T denote: Kilo, Mega, Giga and Tera
  for instance "2G/20M" set 2GB download size and 20MB upload size

=cut

# parameters & constants
my $debug = 0;
my $ul_only = 0;
my $dl_only = 0;
my $server = '3.testdebit.info';
my $test = '';
my $size_upload = '5000M';
my $size_download = '5000M';
my $timeout = 8;
my $csv = 0;
my $ip4only = 0;
my $ip6only = 0;
# cmd line options
GetOptions(
  'server=s'=> \$server,
  'test=s'=> \$test,
  'size=s'=> \&ParseSize,
  'timeout=i' => \$timeout,
  'csv' => \$csv,
  'ul' => \$ul_only,
  'dl' => \$dl_only,
  '-4' => \$ip4only,
  '-6' => \$ip6only,
  'debug' => \$debug,
  'help' => sub { pod2usage(-verbose => 1) }) or pod2usage( {-verbose => 2 });

# parse -size <value>
sub ParseSize {
      my ($n, $v) = @_;
      print("parsing option $n with value $v\n") if $debug;
      my $size_value = qr/[1-9][0-9]*[KMGT]?/;
      if ($v =~ /^($size_value)$/)
      {
        $size_download = $1;
        $size_upload = $1;
        print "Found a single size $1\n" if $debug;
      }
      elsif ($v =~ /^($size_value)\/($size_value)$/) {
        $size_download = $1;
        $size_upload = $2;
        print "Found a dual size $1 and $2\n" if $debug;
      }
      else {die('bad size value');}
}

# when in doubt
print "$0 is running on $^O  \n" if $debug;
printout ("Running on $Config{osname} - $Config{osvers} - $Config{archname}\n");
my $datetime = localtime();
printout ("started at: $datetime\n");

# catch signals
$SIG{INT} = sub { print "Caught a sigint $!\n"; cleanup(); die; };
$SIG{TERM} = sub { print "Caught a sigterm $!\n"; cleanup(); die; };
$SIG{PIPE} = sub { print "Caught a sigpipe $!\n" if $debug; }; # dont remove this or PUT tests will fail if timeout

# null device is OS specific
my $null = ($^O eq 'MSWin32') ? 'NUL' : '/dev/null';
print "null device is $null\n" if $debug;

# csv mode
print ("DATE;SERVER;IP;PROTO4;PORT;PROTO7;CONTENT;BW;DNS;PING;DIR;START;DURATION;TIMEDOUT;SIZE;CODE;TIME\n") if ($csv);

# do all tests
if ($test eq '') {
 while (my $line = <DATA>) {
    print("parsing line: $line\n") if $debug;
    last if ($line =~ "end");
    chomp $line;
    my ($ip, $port, $proto, $type, $direction) = parseTest($line);
    my $size = ($direction eq 'GET') ? $size_download : $size_upload;
    my $r = doTest($ip, $port, $proto, $type, $direction, $size, $timeout);
    print "doTest returned $r" if $debug;
  }
}
# do only a specific test
else
{
  my ($ip, $port, $proto, $type, $direction) = parseTest($test);
  my $size = ($direction eq 'GET') ? $size_download : $size_upload;
  my $r = doTest($ip, $port, $proto, $type, $direction, $size , $timeout);
  print "doTest returned $r" if $debug;
}

$datetime = localtime();
printout ("ended at: $datetime\n");

# clean up
cleanup();

exit;

# -------------------------------------------------------------------------

sub cleanup {
  # nothing more
}

# parse test. TODO some asserts ?
sub parseTest {
  my ($ip, $port, $proto, $type, $direction) = split /\s+/, $_[0];
  print  "parsed D=$direction, IP=$ip, PORT=$port, PROTO=$proto, TYPE=$type\n" if $debug;
  return ($ip, $port, $proto, $type, $direction);
}

# performs a test
# TODO
sub doTest {
  my ($ip, $port, $proto, $type, $direction, $size, $timeout) = @_;
  my $url = "";

  return("skiped ip6") if ($ip4only && $ip eq 6);
  return("skiped ip4") if ($ip6only && $ip eq 4);

  if (($direction eq "POST") && !$dl_only)
  {
    $url = '-T "-" ';
    $url .= " $proto://$server:$port";
  }
  elsif (!$ul_only)
  {
    # http://3totaldebit.info/fichiers/%tailleDL%Mo/%tailleDL%Mo.zip
    # TODO this is so specific to that server...
    $url = "$proto://$server:$port/fichiers/${size}o/${size}o$type";
  }
  # did we build an url ?
  return("skiped") if ($url eq "");

  # TODO: this is curl specific  , put it in doCurl ?
  if (lc $proto eq "https")
  {
    $url = "--insecure $url";
  }

  #perform the Curl
  print "$ip $direction $url\n" if $debug;

  if ($csv) {
    print strftime("%Y-%m-%d %H:%M:%S;", localtime(time)), "$server;$ip;TCP;$port;$proto;$type;";
  }
  else
  {
    printf ("IPv$ip TCP %-6s %6s %5s: ",$port,$proto,$type);
  }

  my $result = doCurl($ip,$direction,$timeout, $size, $url);
  print "$result\n";
  return "ok";
}


# do http download and compute metrics
# args:
#    4 or 6
#    POST or GET
#    timeout
#    rest of the curl args
# TODO: split in 2, seperate curl'ing & calculations from pretty pretting
sub doCurl {
  my ($ip, $dir, $timeout, $size, $url) = @_;
  print("doCurl args = @_\n") if $debug;
  my $sizeparam = ($dir eq 'GET') ? "size_download" : "size_upload";
  my $timeout_cmd = ($timeout == 0) ? "" : "--max-time $timeout";
  my $curlcmd = "curl -$ip -s $timeout_cmd --write-out \"%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{$sizeparam} %{http_code}\" -o $null $url"; #  2>&1 ?
  print "$curlcmd \n" if $debug;
  my $result = '';
  my $curlRC = -1;

  if ($dir eq "GET") {
    $result = `$curlcmd`;
    $curlRC = $? >>8;
  }
  else #assume PUT
  {
    my($wtr, $rdr, $err);
    my $childpid = open3($wtr, $rdr, $err, "$curlcmd");
    $wtr->autoflush(1);
    binmode $wtr;
    my $sent = 0;
    my $totaltosend = Sizetobytes($size);
    print ("size is $size, so total bytes to send is $totaltosend\n") if $debug ;

    my @chunk;
    my $chuck_size = 4096;
    for (my $idx = 0; $idx < $chuck_size; $idx++) {
        $chunk[$idx] = $idx % 256;
    }
    my $pack = pack('C*',@chunk);

    my $childisalive = 1;
    while (1)
    {
      if (waitpid ($childpid,WNOHANG)) {
        print "child ended\n" if $debug;
        $curlRC = $? >> 8;
        $childisalive = 0;
        last;
      }

      print $wtr $pack;
      $sent += $chuck_size ;
      last if ($sent >= $totaltosend);
    }
    close ($wtr);
    $result = <$rdr>;
    if ($childisalive)
    {
      waitpid ($childpid,0);
      $curlRC = $? >> 8;
    }
  }

  print "curl return code = $curlRC\n" if $debug;
  if ($curlRC != 0 && $curlRC != 28) {
    print "!!! curl error for @_ !!! RC = $curlRC\n";
  }
  else {
    # hacky: french locale decimal separator
    $result =~ tr/,/./;
    print "result : $result \n" if $debug;
    my ($time_namelookup, $time_connect, $time_starttransfer, $time_total, $size_transfered, $httpcode) = split / /, $result;
    if ($debug) {
      print "time_namelookup : $time_namelookup\n";
      print "time_connect : $time_connect\n";
      print "time_starttransfer : $time_starttransfer\n";
      print "time_total : $time_total\n";
      print "$sizeparam : $size_transfered bytes\n";
      print "http_code : $httpcode\n";
    }
    # TODO check for more?
    return "error (http $httpcode)" unless $httpcode eq "200" || $httpcode eq "100" || $httpcode eq "405";
    $time_namelookup = $time_namelookup*1000;

    $time_connect *= 1000;
    my $Ping = $time_connect-$time_namelookup;

    $time_starttransfer = $time_starttransfer*1000-$time_connect;

    $time_total *= 1000;
    my $temps_transfert = $time_total-$time_starttransfer;

    my $bw = sprintf("%.2f",  $size_transfered*8/1000/$temps_transfert);

    my $dirLabel= ($dir =~ "POST") ?"Up" : "Down";
    my $timedout = ($curlRC == 28) ? "timeout":'full';
    if ($csv) {
      return "$bw;${time_namelookup};${Ping};$dir;${time_starttransfer};${temps_transfert};$timedout;$size_transfered;$httpcode;$time_total";
    }
    else      {
      $bw = sprintf("%8s",$bw);
      return "$bw Mb/s (DNS:${time_namelookup}ms SYN:${Ping}ms $dir:${time_starttransfer}ms $dirLabel:${temps_transfert}ms:$timedout:$size_transfered)";}
  }
}

sub printout {
  return if ($csv);
  print @_;
}

sub Sizetobytes {
  my $size = $_[0];
  print "converting $size\n" if $debug;
  my $value = qr/[1-9][0-9]*/;
  my $unit = qr/[KMGT]$/;
  if ($size =~ /^($value)($unit)$/)
  {
    if    ($2 eq "K") { $size = $1 * 1000; }
    elsif ($2 eq "M") { $size = $1 * 1000*1000; }
    elsif ($2 eq "G") { $size = $1 * 1000*1000*1000; }
    elsif ($2 eq "T") { $size = $1 * 1000*1000*1000*1000; }
		else
      { die "fatal error in Sizetobytes\n"; }
  }

  return $size;
}
__DATA__
4 80   http  .zip GET
4 80   http  .jpg GET
4 80   http  .mp4 GET
4 80   http  .pdf GET
4 443  https .zip GET
4 443  https .jpg GET
4 554  http  .zip GET
4 554  http  .jpg GET
4 554  http  .mp4 GET
4 993  https .zip GET
4 993  https .jpg GET
4 1194 https .zip GET
4 1194 https .jpg GET
4 6881 http  .zip GET
4 6881 http  .jpg GET
4 8080 http  .zip GET
4 8080 http  .jpg GET
4 8080 http  .mp4 GET
6 80   http  .zip GET
6 80   http  .jpg GET
6 80   http  .mp4 GET
6 443  https .zip GET
6 554  http  .zip GET
6 1194 https .zip GET
6 6881 http  .zip GET
6 8080 http  .zip GET
4 80   http  .zip POST
4 80   http  .jpg POST
4 80   http  .mp4 POST
4 443  https .zip POST
4 554  http  .zip POST
4 1194 https .zip POST
4 6881 http  .zip POST
4 8080 http  .zip POST
6 80   http  .zip POST
6 80   http  .jpg POST
6 80   http  .zip POST
6 443  https .zip POST
6 554  http  .zip POST
6 1194 https .zip POST
6 6881 http  .zip POST
6 8080 http  .zip POST
end
