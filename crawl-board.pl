use v5.18;

use File::Path qw(make_path);

use Mojo::UserAgent;
use Mojo::UserAgent::CookieJar;

sub main {
    my ($board_name, $output_dir) = @_;

    my $ua = Mojo::UserAgent->new;
    $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

    my $ptt_url   = "https://www.ptt.cc";
    my $board_url = "${ptt_url}/bbs/${board_name}/index.html";

    my $tx = $ua->get($board_url);

    my @articles;
    $tx->res->dom->find("a[href*='/bbs/${board_name}/']")->each(
        sub {
            return unless (my $href = $_->attr("href")) =~ m{ / ( M \. [0-9]+ \. A \. [A-Z0-9]{3} ) \.html$}x;
            my $subject = $_->text;
            my $article_id = $1;
            my $article_url = $ptt_url . $href;
            push @articles, {
                subject => $subject,
                url     => $article_url,
                id      => $article_id
            };
        }
    );

    my $output_board_dir = "${output_dir}/${board_name}";
    make_path($output_board_dir);
    for (@articles) {
        my $save_as = "${output_board_dir}/" . $_->{id} . ".html";
        $ua->get($_->{url})->res->content->asset->move_to( $save_as );
        say "==> $save_as";
    }
}

main(@ARGV);
