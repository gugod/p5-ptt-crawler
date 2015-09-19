#!/usr/bin/env perl
use v5.18;
use DDP;
use JSON;
use Mojo::DOM;

use File::Next;
use File::Slurp qw(read_file);

sub extract_article_html {
    my ($html_content) = @_;
    my $article = {};
    my $dom = Mojo::DOM->new($html_content);
    my $main_content = $dom->at("#main-content") or return;
    $main_content->find(".article-metaline")->each(
        sub {
            push @{ $article->{meta} }, [
                $_->at('.article-meta-tag')->text,
                $_->at('.article-meta-value')->text,
            ];
            $_->remove;
        }
    );

    $main_content->find("div.push")->each(
        sub {
            my $o = $_;
            my $tag = $o->at('.push-tag') or return;
            my $userid = $o->at('.push-userid') or return;
            my $content = $o->at('.push-content') or return;
            my $ipdatetime = $o->at('.push-ipdatetime') or return;

            push @{ $article->{push} }, {
                tag        => $tag->text,
                userid     => $userid->text,
                content    => $content->text,
                ipdatetime => $ipdatetime->text,
            };
            $o->remove;
        }
    );

    $article->{body} = $main_content->all_text(0);
    return $article;
}

sub convert_and_save {
    state $JSON = JSON->new->canonical->pretty;

    my ($file) = @_;
    return unless $file =~ m{ / (\w+) / ([\.0-9A-Z]+) \.html$}x;
    my ($board_name, $id) = ($1, $2);

    say "PROCESSING\t$board_name / $id";
    my $html_content = read_file($file, binmode => ":utf8");
    my $article = extract_article_html( $html_content );

    unless ($article) {
        warn "FAIL $file seems to contant no article.";
        return;
    }

    my $output_file = $file =~ s{\.html$}{.json}r;
    open(my $fh, ">:utf8", $output_file) or die $!;
    print $fh $JSON->encode($article);
    close($fh);
    say "==> $output_file";
}

sub main {
    my ($input_dir) = @_;

    my $iter = File::Next::files($input_dir);
    while (defined(my $file = $iter->())) {
        convert_and_save($file);
    }
}

main(@ARGV);
