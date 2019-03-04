#!/usr/bin/env perl

use strict;
use warnings;
use 5.014;
use MetaCPAN::Client;
use Path::Tiny qw( path );
use HTTP::Tiny;
use YAML::XS qw( Load Dump DumpFile );
use Mojo::DOM58;

my $mcpan = MetaCPAN::Client->new;

my $spec = $mcpan->release({
  all => [
    { status => 'latest'   },
    { author => 'PLICEASE' },
  ],
});

my @dist_list;
while(my $item = $spec->next)
{
  push @dist_list, $item->distribution;
}

@dist_list = sort @dist_list;

sub get
{
  my($url) = @_;
  state $http;
  $http ||= HTTP::Tiny->new;
  for(1..10)
  {
    print "GET $url ";
    my $res = $http->get($url);
    if($res->{success})
    {
      print "@{[ $res->{status} ]} @{[ $res->{reason} ]}\n";
      return $res;
    }
    else
    {
      if($res->{status} == 599)
      {
        print "@{[ $res->{status} ]} @{[ $res->{content} ]}\n";
      }
      else
      {
        print "@{[ $res->{status} ]} @{[ $res->{reason} ]}\n";
      }
    }
  }
  die "failed fetch 10x";
}

foreach my $dist (@dist_list)
{
  my $res = get("https://www.cpantesters.org/distro/@{[ substr $dist, 0, 1 ]}/$dist.yml");

  path("yml/$dist.yml")->spew_utf8($res->{content});

  my $list = Load($res->{content});
  foreach my $entry (@$list)
  {
    my $guid = $entry->{guid};
    my $report_path = path('report')
                        ->child(substr($guid, 0,2))
                        ->child(substr($guid, 2,2))
                        ->child($guid);
    next if -f $report_path;

    $report_path->parent->mkpath;
        
    my $res = get("https://www.cpantesters.org/cpan/report/@{[ $entry->{guid} ]}");

    my $text = Mojo::DOM58
      ->new($res->{content})->find('pre')->first->all_text;
    
    $report_path->spew_utf8($text);
  }
}
