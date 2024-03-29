#!/usr/bin/env perl

use strict;
use warnings;
use 5.014;
use MetaCPAN::Client;
use Path::Tiny qw( path );
use HTTP::Tiny;
use YAML::XS qw( Load Dump DumpFile );
use Mojo::DOM58;
use DBI;

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
  push @dist_list, [ $item->distribution, $item->version ];
}

@dist_list = sort { $a->[0] cmp $b->[0] } @dist_list;

sub get
{
  my($url) = @_;
  state $http;
  $http ||= HTTP::Tiny->new;
  foreach my $try (1..10)
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
        my $reason = $res->{content};
        chomp $reason;
        print "@{[ $res->{status} ]} @{[ $reason ]}\n";
      }
      else
      {
        print "@{[ $res->{status} ]} @{[ $res->{reason} ]}\n";
      }
      print "sleep ";
      for(1..$try)
      {
        sleep 1;
        print ".";
      }
      print "\n";
    }
  }
  die "failed fetch 10x";
}

sub insert
{
  my(%meta) = @_;

  state $dbh;
  state $insert;
  state $columns = [qw(
    guid
    csspatch
    cssperl
    dist
    distribution
    distversion
    fulldate
    id
    osname
    ostext
    osvers
    perl
    platform
    postdate
    state
    status
    tester
    type
    uploadid
    version
    cssrelease
  )];

  unless($dbh)
  {
    my $dbh = DBI->connect("dbi:SQLite:dbname=db/meta.sqlite", "", "");


    $dbh->do(qq{
      CREATE TABLE IF NOT EXISTS report (
        guid PRIMARY KEY, @{[ join ', ', grep !/^guid$/, @$columns ]}
      )
    });

    $insert = $dbh->prepare(qq{
      INSERT OR IGNORE INTO report
        (@{[ join ', ', @$columns ]})
      VALUES
        (@{[ join ', ', map { '?' } @$columns ]})
    });
  }

  my $guid = $meta{guid};
  my @values = map { delete $meta{$_} } @$columns;

  if(%meta)
  {
    print Dump(\%meta);
    die "extra keys in report $guid";
  }

  $insert->execute(@values);
}

foreach my $d (@dist_list)
{
  my($dist, $version) = @$d;
  my $res = get("https://www.cpantesters.org/distro/@{[ substr $dist, 0, 1 ]}/$dist.yml");

  #path("db/yml")->mkpath;
  #path("db/yml/$dist.yml")->spew_utf8($res->{content});

  my $list = Load($res->{content});
  foreach my $entry (@$list)
  {
    my $guid = $entry->{guid};

    insert(%$entry);

    #next unless $entry->{version} eq $version;

    my $report_path = path('db/report')
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
