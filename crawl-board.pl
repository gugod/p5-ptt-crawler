use v5.18;

use File::Path qw(make_path);

use Mojo::UserAgent;
use Mojo::UserAgent::CookieJar;

use constant PTT_URL => "https://www.ptt.cc";

sub harvest_articles {
    my ($ua, $url_board_index, $board_name) = @_;

    my $tx = $ua->max_redirects(5)->get($url_board_index);
    if (my $dom = $tx->res->dom->at("form[action='/ask/over18']")) {
        $tx = $ua->post(
            PTT_URL . '/ask/over18',
            form => {
                from => $dom->at("input[name='from']")->attr("value"),
                yes  => "yes"
            }
        );
    }

    my @articles;
    $tx->res->dom->find("a[href*='/bbs/${board_name}/']")->each(
        sub {
            return unless (my $href = $_->attr("href")) =~ m{ / ( M \. [0-9]+ \. A \. [A-Z0-9]{3} ) \.html$}x;
            my $subject = $_->text;
            my $article_id = $1;
            my $article_url = PTT_URL . $href;
            push @articles, {
                subject => $subject,
                url     => $article_url,
                id      => $article_id
            };
        }
    );
    return \@articles;
}

sub main {
    my ($board_name, $output_dir) = @_;

    my $ua = Mojo::UserAgent->new;
    $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

    my $board_url = PTT_URL . "/bbs/${board_name}/index.html";

    my $articles = harvest_articles( $ua, $board_url, $board_name );

    my $output_board_dir = "${output_dir}/${board_name}";
    make_path($output_board_dir);
    for (@$articles) {
        my $save_as = "${output_board_dir}/" . $_->{id} . ".html";
        $ua->get($_->{url})->res->content->asset->move_to( $save_as );
        say "==> $save_as";
    }
}

main(@ARGV);
