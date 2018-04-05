package Munin::Master::HTML;

use strict;
use warnings;

use POSIX;
use HTML::Template::Pro;

use Munin::Master::Utils;

use Munin::Common::Logger;

use File::Basename;
use Data::Dumper;

use CGI::Cookie;

my @times = qw(day week month year);
# Current incarnation of $cgi.
# XXX - this is NOT thread-safe!
my $cgi;

sub handle_request
{
	$cgi = shift;
	my %cookies = CGI::Cookie->fetch;
	my $path = $cgi->path_info();

	# Handle static page now, since there is no need to do any SQL
	if ($path =~ m/static\/(.+)$/) {
		# Emit the static page
		my $page = $1;
		my ($ext) = ($page =~ m/.*\.([^.]+)$/);
		my %mime_types = (
			css => "text/css",
			html => "text/html",
			png => "image/png",
			jpg => "image/jpeg",
			jpeg => "image/jpeg",
			js => "application/javascript",
			svg => "image/svg+xml",
			svgz => "image/svg+xml",
			gif => "image/gif",
		);

		my $filename = get_param("staticdir"). "/$page";
		my $fh = new IO::File("$filename");

		if (! $fh) {
			print "HTTP/1.0 404 Not found\r\n";
			return;
		}

		print "HTTP/1.0 200 OK\r\n";
		print $cgi->header( -type => $mime_types{$ext});
		while (my $line = <$fh>) { print $line; }
		return;
	}

	# Get graph extension (jpg / png / svg / pngx2 /...)
	# Get from cookie if it exists
	my $graph_ext = "png";
	if (defined $cgi->url_param("graph_ext")) {
		$graph_ext = $cgi->url_param("graph_ext");
	}
	elsif (exists $cookies{"graph_ext"}) {
		$graph_ext = $cookies{"graph_ext"}->value;
	}

	# Handle rest-like URL : .json & .xml
	my $output_format = "html";
	if ($path =~ /.(json|xml)$/) {
		$output_format = $1;
		# Replace that part with a ".html" in order to simplify the next handling
		$path =~ s/.(json|xml)$/.html/;
	}


	# Force either a trailing "/" or ".html" to enable simpler url handling: it is like in
	# a subdir from the browser pov
	if ($path eq "" || $path !~ /(\/|\.html)$/) {
		#if ($path eq "") {
		print "HTTP/1.0 301 Redirect Permanent\r\n";
		print $cgi->header(
			-Location => ($cgi->url(-path_info=>1,-query=>1) . "/"),
			-Cache_Control => "public, max-age=14400",  # Cache is valid of 1 day
		);
		return;
	}

	# Remove now the leading "/" as *every* path will have it
	$path =~ s,^/,,;

	# Remove now the ending "/" as *every* dir will have it
	$path =~ s,/$,,;

	# Ok, now SQL is needed to go further
        use DBI;
	my $datafilename = $ENV{MUNIN_DBURL} || "$Munin::Common::Defaults::MUNIN_DBDIR/datafile.sqlite";
        my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename","","") or die $DBI::errstr;

	my $comparison;
	my $template_filename;
	my %template_params = (
		MUNIN_VERSION   => $Munin::Common::Defaults::MUNIN_VERSION,
		TIMESTAMP       => strftime("%Y-%m-%d %T%z (%Z)", localtime),
		R_PATH          => '',
		GRAPH_EXT       => $graph_ext
	);


	# Reduced navigation panel
	$template_params{NAV_PANEL_FOLD} = exists $cookies{"nav_panel_fold"}
		? ($cookies{"nav_panel_fold"}->value eq "true" ? 1 : 0)
		: 0;
	$template_params{NAV_PANEL_FOLD_FORCED} = 0;

	# Common Navigation params
	###################

	# Problems nav
	{
		my $sth = $dbh->prepare_cached("SELECT SUM(critical), SUM(warning), SUM(unknown) FROM ds");
		$sth->execute();
		my ($critical, $warning, $unknown) = $sth->fetchrow_array;
		$template_params{NCRITICAL} = $critical;
		$template_params{NWARNING} = $warning;
		$template_params{NUNKNOWN} = $unknown;
	}

	# Groups nav
	{
		my $sth = $dbh->prepare_cached("SELECT g.name, u.path FROM grp g INNER JOIN url u ON u.id = g.id AND u.type = 'group' WHERE g.p_id = 0 ORDER BY g.name ASC");
		$sth->execute();

		my $rootgroups = [];
		while (my ($_name, $_path) = $sth->fetchrow_array) {
			push @$rootgroups, { NAME => $_name, R_PATH => '', URL => $_path };
		}
		$template_params{ROOTGROUPS} = $rootgroups;
	}

	# Categories nav
	{
		my $sth = $dbh->prepare_cached("SELECT DISTINCT category FROM service_categories ORDER BY category ASC");
		$sth->execute();

		my $globalcats = [];
		while (my ($_category) = $sth->fetchrow_array) {
			my %urls = map { ("URL$_" => "$_category-$_.html") } @times;
			push @$globalcats, {
				R_PATH => '',
				NAME => $_category,
				%urls,
			};
		}
		$template_params{GLOBALCATS} = $globalcats;
	}

	# Handle all the special pages that are not in the url table, but with fixed urls
	if ($path eq "") {
		# Emit overview template
		$template_filename = 'munin-overview.tmpl';

		# Header params
		###################
		{
			$template_params{PATH} = [
				{ } , # XXX - Template says first args has to be empty
				{ "pathname" => "Overview", },
			];
		}

		# Main page
		{
			# Constructing the recursive datastructure.
			# Note that it is quite naive, and not optimized for speed.
			my $sth_grp = $dbh->prepare_cached("SELECT g.id, g.name, u.path FROM grp g INNER JOIN url u ON u.id = g.id AND u.type = 'group' AND p_id = ? ORDER BY g.name ASC");
			my $sth_grp_root = $dbh->prepare_cached("SELECT g.id, g.name, u.path FROM grp g INNER JOIN url u ON u.id = g.id AND u.type = 'group' AND p_id = 0 ORDER BY g.name ASC");
			my $sth_node = $dbh->prepare_cached("SELECT n.id, n.name, u.path, n.path FROM node n INNER JOIN url u ON u.id = n.id AND u.type = 'node' AND n.grp_id = ? ORDER BY n.name ASC");

			$template_params{GROUPS} = _get_params_groups($path, $dbh, $sth_grp, $sth_grp_root, $sth_node, undef, $graph_ext);
			$template_params{NGROUPS} = scalar(@{$template_params{GROUPS}});
		}

		# TODO - We still have to write the bottom navigation links
	} elsif ($path eq "dynazoom.html") {
		# Emit dynamic zoom template

		$template_params{SHOW_ZOOM_JS} = 1;
		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			{ "pathname" => "Dynazoom", "path" => "#" }
		];
		# Content only: when dynazoom page is shown in a modal,
		#   we hide the header & navigation
		$template_params{CONTENT_ONLY} = $cgi->url_param("content_only") || 0;

		$template_filename = "munin-dynazoom.tmpl";
	} elsif ($path eq "problems.html") {
		# Emit problem template

		$template_filename = "munin-problemview.tmpl";

		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			{ "pathname" => "Problems" }
		];

		my $sth = $dbh->prepare_cached("SELECT nu.path, n.name, su.path, s.name, d.critical, d.warning, d.unknown FROM ds d
				LEFT OUTER JOIN service s ON s.id = d.service_id
				LEFT OUTER JOIN url su ON su.id = s.id and su.type = 'service'
				LEFT OUTER JOIN node n ON n.id = s.node_id
				LEFT OUTER JOIN url nu ON nu.id = n.id and nu.type = 'node'
				WHERE d.critical = 1 OR d.warning = 1 OR d.unknown = 1
			");
		$sth->execute();

		my @criticals;
		my @warnings;
		my @unknowns;
		while (my ($_node_url, $_node_name, $_url, $_s_name, $_c, $_w, $_u) = $sth->fetchrow_array) {

			my $img_day = $_url . "-day.png";
			my $img_week = $_url . "-day.png";

			my $item = {
				NODEURL => $_node_url,
				NODENAME => $_node_name,
				URL => $_url,
				URLX => $_url,
				LABEL => $_s_name,

				STATE_CRITICAL => $_c,
				STATE_WARNING => $_w,
				STATE_UNKNOWN => $_u,

				CIMGDAY => $img_day,
				CIMGWEEK => $img_week,
			};

			push @criticals, $item if $_c;
			push @warnings, $item if $_w;
			push @unknowns, $item if $_u;
		}

		# TODO - Create the model (problem)
		$template_params{CRITICAL} = \@criticals;
		$template_params{WARNING} = \@warnings;
		$template_params{UNKNOWN} = \@unknowns;

	} elsif ($path =~ /^([^\/]+)-(day|month|week|year)\.html$/) {
		# That's a category URL
		$template_filename = 'munin-categoryview.tmpl';

		my $category = $1;
		my $time = $2;

		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			{ "pathname" => "Category", },
			{ "pathname" => ucfirst($category), },
		];

		$template_params{CATEGORY} = $category;
		$template_params{TIMERANGE} = $time;

		my $sth_cat;
		if ($category eq 'other') {
			# account for those that explicitly mention 'other' as category
			$sth_cat = $dbh->prepare_cached(
				"SELECT DISTINCT s.name, s.service_title FROM service s
				LEFT JOIN service_categories sc ON s.id = sc.id
				WHERE (sc.category = 'other' OR sc.id IS NULL)
				AND EXISTS (select sa.id from service_attr sa where sa.id = s.id)
				ORDER BY s.name");
			$sth_cat->execute();
		} else {
			$sth_cat = $dbh->prepare_cached(
				"SELECT DISTINCT s.name, s.service_title FROM service s
				INNER JOIN service_categories sc ON s.id = sc.id
				WHERE (sc.category = ?)
				AND EXISTS (select sa.id from service_attr sa where sa.id = s.id)
				ORDER BY s.name");
			$sth_cat->execute($category);
		}

		my @services;
		while (my ($_service, $_service_title) = $sth_cat->fetchrow_array) {
			push @services, _get_params_services_by_name($dbh, $_service, $_service_title, $time, $graph_ext);
		}
		$template_params{SERVICES} = \@services;

		# Force-reduce navigation panel
		$template_params{NAV_PANEL_FOLD} = 1;
		$template_params{NAV_PANEL_FOLD_FORCED} = 1;
	} elsif ($path =~ /^(.+)\/comparison-(day|month|week|year)\.html$/) {
		# That's a comparison URL, handle it as special case of groups
		$path = $1;
		$comparison = $2;
	}


	# Handle normal pages only if not already handled
	goto RENDERING if $template_filename;

	# Remove an eventual [/index].html
	$path =~ s/(\/index)?\.html$//;

	my $sth_url = $dbh->prepare_cached("SELECT id, type FROM url WHERE path = ?");
	$sth_url->execute($path);
	my ($id, $type) = $sth_url->fetchrow_array;

	if (! defined $id) {
		# Not found
		print "HTTP/1.0 404 Not found\r\n";
		return;
	} elsif ($type eq "group") {
		# Shared code for group views and comparison views

		# Constructing the recursive datastructure.
		# Note that it is quite naive, and not optimized for speed.
		my $sth_grp = $dbh->prepare_cached("SELECT g.id, g.name, u.path FROM grp g INNER JOIN url u ON u.id = g.id AND u.type = 'group' AND p_id = ? ORDER BY g.name ASC");
		my $sth_grp_root = $dbh->prepare_cached("SELECT g.id, g.name, u.path FROM grp g INNER JOIN url u ON u.id = g.id AND u.type = 'group' AND p_id = 0 ORDER BY g.name ASC");
		my $sth_node = $dbh->prepare_cached("SELECT n.id, n.name, u.path, n.path FROM node n INNER JOIN url u ON u.id = n.id AND u.type = 'node' AND n.grp_id = ? ORDER BY n.name ASC");

		my $sth_p_id = $dbh->prepare_cached("SELECT g.p_id FROM grp g WHERE g.id = ?");
		$sth_p_id->execute($id);
		my ($_p_id) = $sth_p_id->fetchrow_array;
		my $sth_peer;

		# Check for top level groups
		if (defined $_p_id) {
			$sth_peer = $sth_grp;
			$sth_peer->execute($id);
		} else {
			$sth_peer = $sth_grp_root;
			$sth_peer->execute();
		}

		# Construct list of peers
		my $peers = [];
		while (my (undef, $_name, $_url) = $sth_peer->fetchrow_array) {
			$_url =~ s!/$!!;
			push @$peers, { NAME => $_name, LINK => '../' . basename($_url) . '/' };
		}

		$template_params{PEERS} = $peers;
		$template_params{LARGESET} = 1;
		$template_params{INFO_OPTION} = 'Groups on this level';

		# Generate navigational links
		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			url_to_path($path),
		];

		# hack: use the last element of the path as the name
		$template_params{NAME} = $template_params{PATH}[-1]{'pathname'};

		if ($comparison) {
			# Emit group comparison template
			$template_filename = "munin-comparison.tmpl";

			$template_params{TIMERANGE} = $comparison;

			# Get all categories in this group
			my $sth_cat = $dbh->prepare_cached(
				"SELECT DISTINCT sa_c.category cat FROM node n
				INNER JOIN service s ON s.node_id = n.id
				INNER JOIN service_categories sa_c ON sa_c.id = s.id
				WHERE n.grp_id = ? ORDER BY sa_c.category ASC");
			$sth_cat->execute($id);

			$template_params{CATEGORIES} = [];
			while (my ($cat_name) = $sth_cat->fetchrow_array) {
				push @{$template_params{CATEGORIES}}, _get_params_services_for_comparison($path, $dbh, $cat_name, $id, $graph_ext, $comparison);
			}

			# Force-reduce navigation panel
			$template_params{NAV_PANEL_FOLD} = 1;
			$template_params{NAV_PANEL_FOLD_FORCED} = 1;
		} else {
			# Emit group template
			$template_filename = 'munin-domainview.tmpl';

			# Main page
			$template_params{GROUPS} = _get_params_groups($path, $dbh, $sth_grp, $sth_grp_root, $sth_node, $id, $graph_ext);
			$template_params{NGROUPS} = scalar(@{$template_params{GROUPS}});

			# Shows "[ d w m y ]"
			# comparison only makes sense if there are 2 or more nodes
			$template_params{COMPARE} = 1 if
				1 < scalar grep { defined($_->{'NCATEGORIES'}) && $_->{'NCATEGORIES'} } @{$template_params{GROUPS}};
		}

	} elsif ($type eq "node") {
		# Emit node template
		$template_filename = 'munin-nodeview.tmpl';

		# Construct list of peers
		my $sth_peer = $dbh->prepare_cached(
			"SELECT n.name, u.path FROM node n
			INNER JOIN url u ON n.id = u.id AND u.type = 'node'
			WHERE n.grp_id = (SELECT n.grp_id FROM node n WHERE n.id = ?)
			ORDER BY n.name ASC");
		$sth_peer->execute($id);

		my $peers = [];
		while (my ($_name, $_url) = $sth_peer->fetchrow_array) {
			push @$peers, { NAME => $_name, LINK => '../' . basename($_url) . "/" };
		}

		$template_params{PEERS} = $peers;
		$template_params{LARGESET} = 1;
		$template_params{INFO_OPTION} = 'Nodes on this level';

		my $sth_category = $dbh->prepare(
			"SELECT DISTINCT sc.category as graph_category FROM service s
			INNER JOIN service_categories sc ON sc.id = s.id
			WHERE s.node_id = ?
			ORDER BY graph_category");
		$sth_category->execute($id);

		my $categories = [];
		while (my ($_category_name) = $sth_category->fetchrow_array) {
			push @$categories, _get_params_services($path, $dbh, $_category_name, undef, $id, $graph_ext);
		}

		$template_params{CATEGORIES} = $categories;
		$template_params{NCATEGORIES} = scalar(@$categories);

		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			url_to_path($path),
		];

		$template_params{NAME} = $template_params{PATH}[-1]{'pathname'};

	} elsif ($type eq "service") {
		# Emit service template
		$template_filename = 'munin-serviceview.tmpl';

		my $sth;

		$sth = $dbh->prepare_cached("SELECT name,service_title,graph_info,subgraphs,category,
									(SELECT MAX(warning) FROM ds WHERE service_id = service.id) as state_warning,
									(SELECT MAX(critical) FROM ds WHERE service_id = service.id) as state_critical
									FROM service
									LEFT JOIN service_categories ON service.id = service_categories.id
									WHERE service.id = ?");
		$sth->execute($id);
		my ($graph_name, $graph_title, $graph_info, $multigraph, $category, $state_warning, $state_critical) = $sth->fetchrow_array();

		$sth = $dbh->prepare_cached("SELECT category FROM service_categories WHERE id = ?");
		$sth->execute($id);
		my ($graph_category) = $sth->fetchrow_array();

		$sth = $dbh->prepare_cached("SELECT n.id FROM node n INNER JOIN service s ON s.node_id = n.id WHERE s.id = ?");
		$sth->execute($id);
		my ($node_id) = $sth->fetchrow_array();

		# Generate peers
		my ($graph_parent) = ($graph_name =~ /^(.*)\./);
		$template_params{PEERS} = [ map {
			(my $name = basename($_->{"URLX"}, ".html")) =~ tr/_/ /;
			{ NAME => $name, LINK => $multigraph ? ("../" . $_->{URLX}) : $_->{URLX}, }
		} @{_get_params_services(dirname($path), $dbh, $graph_category, $graph_parent, $node_id, $graph_ext)->{SERVICES}} ];
		$template_params{LARGESET} = 1;
		$template_params{INFO_OPTION} = 'Graphs in same category';

		$template_params{PATH} = [
			# first args should have path and r_path for backlink to overview
			{ "r_path" => url_absolutize(''), "path" => url_absolutize(''), },
			url_to_path($path),
		];

		$template_params{CATEGORY} = ucfirst($graph_category);

		if ($multigraph) {
			# Emit node template for multigraphs
			$template_filename = 'munin-nodeview.tmpl';

			my @categories = (_get_params_services($path, $dbh, $graph_category, $graph_name, $node_id, $graph_ext));
			$template_params{CATEGORIES} = \@categories;
			$template_params{NCATEGORIES} = scalar(@categories);
			$template_params{NAME} = $template_params{PATH}[-1]{'pathname'};

			goto RENDERING;
		}

		# Create the params
		my %service_template_params;
		$service_template_params{FIELDINFO} = _get_params_fields($dbh, $id);
		my $cgi_graph_url = '/';
		my $epoch_now = time;
		my %epoch_start = (
			day => $epoch_now - (3600 * 30),
			week => $epoch_now - (3600 * 24 * 8),
			month => $epoch_now - (3600 * 24 * 33),
			year => $epoch_now - (3600 * 24 * 400),
		);

		# Add some more information (graph name, title, category, nodeview path)
		$service_template_params{GRAPH_NAME} = $graph_name;
		$service_template_params{GRAPH_TITLE} = $graph_title;
		$service_template_params{CATEGORY} = $category;
		$service_template_params{NODEVIEW_PATH} = "/" . dirname($path);

		# Problems
		$service_template_params{STATE_WARNING} = $state_warning;
		$service_template_params{STATE_CRITICAL} = $state_critical;

		for my $t (@times) {
			my $epoch = "start_epoch=$epoch_start{$t}&stop_epoch=$epoch_now";
			$service_template_params{"ZOOM$t"} = "/dynazoom.html?cgiurl_graph=$cgi_graph_url" .
				"&plugin_name=$path&size_x=800&size_y=400&$epoch";
			$service_template_params{"IMG$t"} = $cgi_graph_url . "$path-$t.$graph_ext";
		}

		# template uses loop for no apparent reason
		$service_template_params{GRAPHINFO} = [ { info => $graph_info } ];

		$template_params{SERVICES} = [ \%service_template_params,];
	}

RENDERING:
	if (! $template_filename ) {
		# Unknown
		print "HTTP/1.0 404 Not found\r\n";
		return;
	}

	if ($output_format eq "html") {
		print "HTTP/1.0 200 OK\r\n";
		print $cgi->header( "-Content-Type" => "text/html", );
		my $template = HTML::Template::Pro->new(
			filename => "$Munin::Common::Defaults::MUNIN_CONFDIR/templates/$template_filename",
			loop_context_vars => 1,
		);

		my $is_dump_enabled = $cgi->url_param("dump");
		if ($is_dump_enabled) {
			use Data::Dumper;
			local $Data::Dumper::Terse = 1;
			local $Data::Dumper::Sortkeys = 1;
			local $Data::Dumper::Sparseseen = 1;
			local $Data::Dumper::Deepcopy = 1;
			local $Data::Dumper::Indent = 1;

			$template_params{DEBUG} = Dumper(\%template_params);
		}

		$template->param(%template_params);

		# We cannot use "print_to => \*STDOUT" since it does *NOT* work with FastCGI
		print $template->output();
	} elsif ($output_format eq "xml") {
		print "HTTP/1.0 200 OK\r\n";
		print $cgi->header( "-Content-Type" => "text/xml", );

		use XML::Dumper;
		print pl2xml( \%template_params );
	} elsif ($output_format eq "json") {
		print "HTTP/1.0 200 OK\r\n";
		print $cgi->header( "-Content-Type" => "application/json", );

		use JSON;
		print encode_json( \%template_params );
	}
}

sub _get_params_groups {
	my ($path, $dbh, $sth_grp_normal, $sth_grp_root, $sth_node, $g_id, $graph_ext) = @_;

	my $sth_grp;
	if (defined $g_id) {
		$sth_grp = $sth_grp_normal;
		$sth_grp->execute($g_id);
	} else {
		$sth_grp = $sth_grp_root;
		$sth_grp->execute();
	}

	my $groups = [];

	# This function is recursive and reuses the prepared statements,
	# so we need to save the results first.
	my $_sth_grp_data = $sth_grp->fetchall_arrayref;
	foreach my $row (@$_sth_grp_data) {
		my ($_g_id, $_name, $_path) = @$row;
		my $_groups = _get_params_groups($path, $dbh, $sth_grp_normal, $sth_grp_root, $sth_node, $_g_id, $graph_ext);
		my $_compare_groups = scalar grep { defined($_->{'NCATEGORIES'}) && $_->{'NCATEGORIES'} } @$_groups;
		push @$groups, {
			NAME => $_name,
			URL => "$_path/",
			GROUPS => $_groups,
			NGROUPS => scalar(@$_groups),
			# comparison only makes sense if there are 2 or more nodes
			COMPARE => ($_compare_groups > 1 ? 1 : 0),
			R_PATH => '',
			PATH => [
				{ PATH => '..', PATHNAME => undef, },
				url_to_path($_path),
			],
		};
	}

	# Add the nodes
	$sth_node->execute($g_id);
	while (my ($_n_id, $_name, $_path, $_node_path) = $sth_node->fetchrow_array) {
		my $sth = $dbh->prepare_cached("SELECT DISTINCT sc.category FROM service s INNER JOIN service_categories sc ON sc.id = s.id WHERE s.node_id = ? ORDER BY sc.category ASC");
		$sth->execute($_n_id);

		# trim off current path from target's path
		substr($_path, 0, 1 + length($path)) = '' if $path;

		my $categories = [];
		while (my ($_category_name) = $sth->fetchrow_array) {
			my $category = _get_params_services($path, $dbh, $_category_name, undef, $_n_id, $graph_ext);
			$category->{URLX} = "$_path/" . "#" . $_category_name;
			$category->{URL} = $category->{URLX}; # For category in overview
			push @$categories, $category;
		}

		# No Category found, use a dummy one.
		$categories = [ { }, ] unless scalar @$categories;

		push @$groups, {
			CATEGORIES => $categories,
			NCATEGORIES => (scalar @$categories), # This is a node.
			NAME => $_name,
			URL => "$_path/",
			URLX => "$_path/",
			GROUPS => [],
		};
	}

	return $groups;
}

sub _get_params_services_for_comparison {
	my ($basepath, $dbh, $category_name, $grp_id, $graph_ext, $comparison) = @_;

	# Get all possible services with the specified category under the specified group
	my $sth_srv = $dbh->prepare_cached(
		"SELECT DISTINCT s.name, s.service_title FROM service s
		INNER JOIN node n ON s.node_id = n.id
		INNER JOIN service_categories sa_c ON sa_c.id = s.id AND sa_c.category = ?
		WHERE n.grp_id = ? ORDER BY s.name ASC");

	# Get node and service pairs
	my $sth_node = $dbh->prepare_cached(
		"SELECT n.name, u.path, s.path, s.title FROM node n
		INNER JOIN url u ON u.id = n.id AND u.type = 'node'
		LEFT JOIN
			( SELECT s.id AS id, s.node_id AS node_id, s.service_title AS title, u_s.path AS path FROM service s
			INNER JOIN url u_s ON s.id = u_s.id AND u_s.type = 'service'
			WHERE s.name = ? ) AS s ON n.id = s.node_id
		WHERE n.grp_id = ?
		ORDER BY n.name, s.title ASC");

	my %category = (
		GROUPNAME => $category_name,
		SERVICES => [],
	);

	$sth_srv->execute($category_name, $grp_id);
	while (my ($service_name, $service_title) = $sth_srv->fetchrow_array) {
		# Skip multigraph sub-graphs
		next if $service_name =~ /\./;

		my @nodes;
		$sth_node->execute($service_name, $grp_id);
		while (my ($node_name, $node_url, $srv_url, $srv_label) = $sth_node->fetchrow_array) {
			my $_srv_url = "$srv_url.html" if defined $srv_url;
			my $_img_url = "/$srv_url-$comparison.$graph_ext" if defined $srv_url;
			push @nodes, {
				R_PATH => '',
				NODENAME => $node_name,
				URL1 => substr($node_url, length($basepath) + 1),
				LABEL => $srv_label,
				URL => $_srv_url,
				CIMG => $_img_url,
			};
		}

		push @{$category{SERVICES}}, { NODES => \@nodes, SERVICENAME => $service_name, SERVICETITLE => $service_title };
	}

	return \%category;
}

# This is only called for category views, which start with the root URL,
# so no need to handle basepath or multigraph parents for relative URLs
sub _get_params_services_by_name {
	my ($dbh, $service_name, $service_title, $time, $graph_ext) = @_;

	# TODO warning/critical state (use SUM sub-queries?)
	# XXX this may be slow
	my $sth = $dbh->prepare_cached(
		"SELECT s.id, s.service_title as service_title, s.subgraphs as subgraphs, u.path AS url,
		n.name AS node_name, u_n.path AS node_url
		FROM service s
		INNER JOIN url u ON u.id = s.id AND u.type = 'service'
		INNER JOIN node n ON n.id = s.node_id
		INNER JOIN url u_n ON u_n.id = s.node_id AND u_n.type = 'node'
		WHERE s.name = ?
		ORDER BY node_name ASC");
	$sth->execute($service_name);

	my $_url_var = "CIMG" . uc($time);
	my $_time_var = "TIME" . uc($time);
	my @graphs;
	while (my ($_s_id, $_service_title, $_subgraphs, $_url, $_node_name, $_node_url) = $sth->fetchrow_array) {
		push @graphs, {
			HOST_URL => "$_node_url/",
			NODENAME => $_node_name,
			LABEL => $_service_title,
			URLX => $_url . ($_subgraphs ? "/" : ".html"),
			"CIMG$time" => "/$_url-$time.$graph_ext",
			"TIME$time" => 1,
		};
	}

	return {
		NAME => $service_name,
		TITLE => $service_title,
		GRAPHS => \@graphs,
	};
}

sub _get_params_services {
	my ($base_path, $dbh, $category_name, $multigraph_parent, $node_id, $graph_ext) = @_;

	my $sth = $dbh->prepare_cached("SELECT s.id, s.name, s.service_title as service_title, s.subgraphs as subgraphs, u.path AS url,
									(SELECT MAX(warning) FROM ds WHERE service_id = s.id) as state_warning,
									(SELECT MAX(critical) FROM ds WHERE service_id = s.id) as state_critical
		FROM service s
		INNER JOIN service_categories sa_c ON sa_c.id = s.id AND sa_c.category = ?
		INNER JOIN url u ON u.id = s.id AND u.type = 'service'
		WHERE s.node_id = ?
		AND EXISTS (select sa.id from service_attr sa where sa.id = s.id)
		ORDER BY service_title ASC");
	$sth->execute($category_name, $node_id);

	my $services = [];

	# Group-level sums
	my $n_warnings = 0;
	my $n_criticals = 0;

	while (my ($_s_id, $_s_name, $_service_title, $_subgraphs, $_url, $_state_warning, $_state_critical) = $sth->fetchrow_array) {
		# Skip sub-graphs if not in multigraph
		next if not $multigraph_parent and $_s_name =~ /\./;
		# Skip unrelated graphs if in multigraph
		next if $multigraph_parent and $_s_name !~ /^$multigraph_parent\./;

		$n_warnings += $_state_warning;
		$n_criticals += $_state_critical;

		my %imgs = map { ("IMG$_" => "/$_url-$_.$graph_ext") } @times;
		push @$services, {
			NAME => $_service_title,
			URLX => substr($_url, 1 + length($base_path)) . ($_subgraphs ? "/" : ".html"),
			STATE_WARNING => $_state_warning,
			STATE_CRITICAL => $_state_critical,
			%imgs
		};
	}

	return {
		NAME => $category_name,
		SERVICES => $services,
		STATE_WARNING => $n_warnings > 0,
		STATE_CRITICAL => $n_criticals > 0
	};
}

sub _get_params_fields {
	my ($dbh, $service_id) = @_;

	my $sth_ds = $dbh->prepare_cached("
		SELECT ds.name, ds.warning, ds.critical,
		a_g.value, a_l.value, IFNULL(a_t.value, 'GAUGE'), a_w.value, a_c.value, a_i.value
		FROM ds
		LEFT JOIN ds_attr a_g ON ds.id = a_g.id AND a_g.name = 'graph'
		LEFT JOIN ds_attr a_l ON ds.id = a_l.id AND a_l.name = 'label'
		LEFT JOIN ds_attr a_t ON ds.id = a_t.id AND a_t.name = 'type'
		LEFT JOIN ds_attr a_w ON ds.id = a_w.id AND a_w.name = 'warning'
		LEFT JOIN ds_attr a_c ON ds.id = a_c.id AND a_c.name = 'critical'
		LEFT JOIN ds_attr a_i ON ds.id = a_i.id AND a_i.name = 'info'
		WHERE ds.service_id = ?
		ORDER BY ds.id ASC");
	$sth_ds->execute($service_id);

	my @fields;
	while (my ($_ds_name, $_ds_s_warn, $_ds_s_crit, $_ds_graph, $_ds_label, $_ds_type, $_ds_warn, $_ds_crit, $_ds_info) =
			$sth_ds->fetchrow_array) {
		next if $_ds_graph && $_ds_graph eq 'no';

		push @fields, {
			FIELD => $_ds_name,
			STATE_WARNING => $_ds_s_warn,
			STATE_CRITICAL => $_ds_s_crit,
			LABEL => $_ds_label,
			TYPE => lc($_ds_type),
			WARN => $_ds_warn,
			CRIT => $_ds_crit,
			INFO => $_ds_info,
		};
	}

	return \@fields;
}

sub get_param
{
	my ($param) = @_;

	# Ok, now SQL is needed to go further
        use DBI;
	my $datafilename = $ENV{MUNIN_DBURL} || "$Munin::Common::Defaults::MUNIN_DBDIR/datafile.sqlite";
        my $dbh = DBI->connect("dbi:SQLite:dbname=$datafilename","","") or die $DBI::errstr;

	my ($value) = $dbh->selectrow_array("SELECT value FROM param WHERE name = ?", undef, ($param));

	return $value;
}

sub url_to_path
{
	my ($url) = @_;

	my @paths = split m!/!, $url;

	@paths = map {
		(my $name = $paths[$_]) =~ tr/_/ /;
		{
			'pathname' => $name,
			'path' => url_absolutize(join '/', @paths[0..$_]) . '/',
			'switchable' => 1
		}
	} 0..$#paths;

	delete $paths[-1]{'path'};

	return @paths;
}

sub url_absolutize
{
	my ($url, $omit_first_slash) = @_;
	my $url_a = '/' . $url;
	$url_a = substr($url_a, 1) if $omit_first_slash;
	return $url_a;
}

1;
