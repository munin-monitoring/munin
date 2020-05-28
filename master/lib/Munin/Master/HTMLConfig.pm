package Munin::Master::HTMLConfig;

use warnings;
use strict;

use Exporter;
our (@ISA, @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(generate_config get_peer_nodes);

use POSIX qw(strftime);
use Getopt::Long;
use Time::HiRes;
use Scalar::Util qw( weaken );

use Munin::Master::Logger;
use Munin::Master::Utils;
use Data::Dumper;

use Log::Log4perl qw( :easy );

my @times = ("day", "week", "month", "year");

my $DEBUG = 0;
my $INDEX_FILENAME = "index.html";

my $config;
my $limits;
my $cache;

my $categories;
my $problems;

sub generate_config {
    my $use_cache = shift;
    if ($use_cache) {
	$cache = undef; # undef, for RAM usage
	# if there is some cache, use it (for cgi)
    	my $newcache = munin_readconfig_part('htmlconf', 1);
	if (defined $newcache) {
		$cache = $newcache;
		return $cache;
	}
    }
    $categories = {};
    $problems = {"criticals" => [], "warnings" => [], "unknowns" => []};
    my $rev = munin_configpart_revision();

    $config = munin_readconfig_part('datafile', 0);
    initiate_cgiurl_graph(); # we don't set a default like for others
    if ($rev != munin_configpart_revision()) {
	# convert config for html generation: reorder nodes to their rightful group
	node_reorder($config);
    }

    $limits = munin_readconfig_part("limits");
    # if only limits changed, still update our cache
    if ($rev != munin_configpart_revision()) {
	$cache = undef; # undef, for RAM usage
	$cache = get_group_tree($config);
    }

    return $cache;
}

sub node_reorder {
	my $totalconfig = shift;
	my $group = shift || $config;
	my $children = munin_get_sorted_children($group);
	# traverse group
	foreach my $child (@$children) {
		# if this is a node
		if(defined $child->{'address'}){
			# if renaming is active
			if(defined $child->{"html_rename"}){
				(my $groups, my $name) = munin_get_host_path_from_string($child->{"html_rename"});
				
				# add the node at its new place
				my $currentgroup = $totalconfig;
				foreach my $local_group (@$groups){
					if(!defined $currentgroup->{$local_group}){
						$currentgroup->{$local_group} = {'#%#name' => $local_group, '#%#parent' => $currentgroup};
						weaken($currentgroup->{$local_group}{'#%#parent'});
					}
					$currentgroup = $currentgroup->{$local_group};
				}

				if(defined $currentgroup->{$name}){
					ERROR $child->{"html_rename"} . " already exists. Renaming not possible.";
				} else {
					# remove node from structure
					undef $group->{$child->{"#%#name"}};
					
					# change name into new name
					$child->{"#%#origname"} = $child->{"#%#name"};
					$child->{"#%#name"} = $name;
					
					# add to new group
					$child->{"#%#origparent"} = $group;
					$currentgroup->{$name} = $child;
					$child->{"#%#parent"} = $currentgroup;
					weaken($child->{"#%#parent"});
				}
			}
		} else {
			# reorder group
			node_reorder($totalconfig, $child);
		}
	}
}

sub initiate_cgiurl_graph {
    if (!defined $config->{'cgiurl_graph'}) {
        if (defined $config->{'cgiurl'}) {
            $config->{'cgiurl_graph'} = $config->{'cgiurl'} . "/munin-cgi-graph";
        }
        else {
            $config->{'cgiurl_graph'} = "/munin-cgi/munin-cgi-graph";
        }
		DEBUG "[DEBUG] Determined that cgiurl_graph is ".$config->{'cgiurl_graph'};
    }
}

sub add_graph_to_categories {
	my $srv = shift;
	my $category = $srv->{"category"};
	my $srvname = $srv->{"label"};
	if(!defined ($categories->{$category})){
		$categories->{$category} = {};
	}
	if(!defined ($categories->{$category}->{$srvname})){
		$categories->{$category}->{$srvname} = [];
	}
	push @{$categories->{$category}->{$srvname}}, $srv;
}

sub get_group_tree {
    my $hash    = shift;
    my $base    = shift || "";

    my $graphs  = [];     # Pushy array of graphs, [ { name => 'cpu'}, ...]
    my $groups  = [];     # Slices of the $config hash
	my $cattrav = {};     # Categories, array of strings
    my $cats    = [];     # Array of graph information ('categories')
    my $path    = [];     # (temporary) array of paths relevant to . (here)
    my $rpath   = undef;
    my $visible = 0;
    my $css_name;

    my $children = munin_get_sorted_children($hash);

    foreach my $child (@$children) {
        next unless defined $child and ref($child) eq "HASH" and keys %$child;

		$child->{"#%#ParentsNameAsString"} = munin_get_node_name($hash); # TODO: is this value used anywhere?

        if (defined $child->{"graph_title"} and munin_get_bool($child, "graph", 1)) { #graph
		    $child->{'#%#is_service'} = 1; # TODO: is this value used anywhere?
			my $childname = munin_get_node_name($child);
			my $childnode = generate_service_templates($child);
			push @$graphs, {"name" => $childname};
			$childnode->{'name'} = $child->{"graph_title"};
			# used in category view and comparison view for nested (multigraph) services
			$childnode->{'nodename'} = munin_get_parent_name($hash);
			add_graph_to_categories($childnode);

		    # Make sure the link gets right even if the service has subservices
	    	if (munin_has_subservices ($child)) {
				$childnode->{'url'}  = $base . $childname . "/$INDEX_FILENAME"; #TODO: html generation should generate urls
		    } else {
				$childnode->{'url'}  = $base . $childname . ".html"; #TODO: html generation should generate urls
	    	}

            $childnode->{'host_url'}  = $base . $INDEX_FILENAME;

            #TODO: Think of a nicer way to generate relative urls (reference #1)
			for (my $shrinkpath = $childnode->{'url'}, my $counter = 0;
			 $shrinkpath;
			 $shrinkpath =~ s/^[^\/]+\/?//, $counter++)
	    	{
                die ("Munin::Master::HTMLConfig ran into an endless loop") if ($counter >= 100);
                $childnode->{'url' . $counter} = $shrinkpath;
            }

            push @{$cattrav->{lc munin_get($child, "graph_category", "other")}}, $childnode;

		    # If this is a multigraph plugin there may be sub-graphs.
		    push( @$groups, grep {defined $_} get_group_tree($child, $base.munin_get_node_name($child)."/"));

            $visible = 1;
		}
        elsif (ref($child) eq "HASH" and !defined $child->{"graph_title"}) { #group
			push( @$groups, grep {defined $_} get_group_tree($child, $base.munin_get_node_name($child) . "/"));

			if (scalar @$groups) {
				$visible = 1;
		    }
		}
    }

	foreach my $group (@$groups) {
		$group->{'peers'} = get_peer_nodes($group->{"#%#hash"}, lc munin_get($group->{"#%#hash"}, "graph_category", "other"));
	}

    return unless $visible;

    $hash->{'#%#visible'} = 1; # TODO: is this value used anywhere?

    # We need the categories in another format.
    foreach my $cat (sort keys %$cattrav) {
        my $obj = {};
        $obj->{'name'}     = $cat;
        $obj->{'url'}      = $base . "${INDEX_FILENAME}#" . $cat;
        $obj->{'services'} = [sort {lc($a->{'name'}) cmp lc($b->{'name'})}
                @{$cattrav->{$cat}}];
        $obj->{'state_' . lc munin_category_status($hash, $limits, $cat, 1)}
            = 1;
		#TODO: shrinkpath reference #2
        for (
            my $shrinkpath = $obj->{'url'}, my $counter = 0;
            $shrinkpath =~ /\//;
            $shrinkpath =~ s/^[^\/]+\/*//, $counter++
            ) {
            die ("Munin::Master::HTMLConfig ran into an endless loop") if ($counter >= 100);
            $obj->{'url' . $counter} = $shrinkpath;
        }
        push @$cats, $obj;
    }

    # ...and we need a couple of paths available.
	# TODO: think of a nicer way to generate urls
    @$path = reverse map {
        {
            "pathname" => $_,
            "path" => (
                defined $rpath
                ? ($rpath .= "../") . $INDEX_FILENAME
                : ($rpath = ""))}
    } reverse(undef, split('\/', $base));
	
	# TODO: think of a nicer way to generate urls
    my $root_path = get_root_path($path);

    # We need a bit more info for the comparison templates
    my $compare         = munin_get_bool($hash, "compare", 1);
    my $comparecats = [];
    my $comparegroups = [];
	if($compare){
      ($compare, $comparecats, $comparegroups) = generate_compare_groups($groups);
    }
	my %group_hash = (map {$_->{'name'} => $_} @{$groups});   
 
	my $ret = {
        "name"     => munin_get_node_name($hash),
        "url"      => $base . $INDEX_FILENAME,
        "path"     => $path,
		"#%#hash"     => $hash,
        "depth" => scalar(my @splitted_base = split("/", $base . $INDEX_FILENAME))
            - 1,
        "filename"           => munin_get_html_filename($hash),
        "css_name"           => $css_name,
        "root_path"          => $root_path,
        "groups"             => $groups,
		"groups_hash"		 => \%group_hash,
        "graphs"             => $graphs,
        "multigraph"         => munin_has_subservices ($hash),
        "categories"         => $cats,
        "ngroups"            => scalar(@$groups),
        "ngraphs"            => scalar(@$graphs),
        "ncategories"        => scalar(@$cats),
        "compare"            => $compare,
        "comparegroups"      => $comparegroups,
        "ncomparegroups"     => scalar(@$comparegroups),
        "comparecategories"  => $comparecats,
        "ncomparecategories" => scalar(@$comparecats),
    };


	if($ret->{'depth'} == 0){ #root node does not have peer nodes
		# add categories
		my $catarray = [];
		foreach (sort keys %{$categories}) {
			my $currentcat = $categories->{$_};
			my $srvarray = [];
			foreach (sort keys %{$currentcat}) {
				my $srv_nodename = $_;
				$srv_nodename =~ s/ /_/g;
				my $srv = {
					"graphs" => $currentcat->{$_},
					"name" => $_,
					"service" => $srv_nodename,
				};
				push @$srvarray, $srv
			}
			my $filename = munin_get_html_filename($hash);
			$filename =~ s/index.html$/$_/;
			my $cat = {
				"name" => $_,
				"urlday" => "$_-day.html",
				"urlweek" => "$_-week.html",
				"urlmonth" => "$_-month.html",
				"urlyear" => "$_-year.html",
				"path" => $path,
				"graphs" => $srvarray,
				"filename-day" => $filename . "-day.html",
				"filename-week" => $filename . "-week.html",
				"filename-month" => $filename . "-month.html",
				"filename-year" => $filename . "-year.html",
			};
			push @$catarray, $cat;
		}
		$ret->{"problems"} = $problems;
		$ret->{"globalcats"} = $catarray;
		$ret->{"nglobalcats"} = scalar(@$catarray);
	}

    #TODO: shrinkpath reference #3
	if ($ret->{'url'} ne "/index.html") {
        for (
            my $shrinkpath = $ret->{'url'}, my $counter = 0;
            $shrinkpath =~ /\//;
            $shrinkpath =~ s/^[^\/]+\/*//, $counter++
            ) {
            die ("Munin::Master::HTMLConfig ran into an endless loop") if ($counter >= 100);
            $ret->{'url' . $counter} = $shrinkpath;
        }
    }

    return $ret;
}

sub generate_compare_groups {
  my $groups = shift;
  my $comparecats     = [];
  my $comparecatshash = {};
  my $comparegroups   = [];

  foreach my $tmpgroup (@$groups) {

    # First we gather a bit of data into comparecatshash...
    if ($tmpgroup->{'ngraphs'} > 0 && !$tmpgroup->{"multigraph"}) { # no compare links for multigraphs
      push @$comparegroups, $tmpgroup;
      foreach my $tmpcat (@{$tmpgroup->{'categories'}}) {
        $comparecatshash->{$tmpcat->{'name'}}->{'groupname'} = $tmpcat->{'name'};
        foreach my $tmpserv (@{$tmpcat->{'services'}}) {
          $comparecatshash->{$tmpcat->{'name'}}->{'services'}->{$tmpserv->{'name'}}->{'nodes'}->{$tmpgroup->{'name'}} = $tmpserv;
          $comparecatshash->{$tmpcat->{'name'}}->{'services'}->{$tmpserv->{'name'}}->{'nodes'}->{$tmpgroup->{'name'}}->{'nodename'} = $tmpgroup->{'name'};
          $comparecatshash->{$tmpcat->{'name'}}->{'services'}->{$tmpserv->{'name'}}->{'nodes'}->{$tmpgroup->{'name'}}->{'nodeurl'} = $tmpgroup->{'url'};
        }
      }
    }
  }
  if (scalar @$comparegroups <= 1) {
    return (0, [], []); # ($compare, $comparecats, $comparegroups)
  }

  # restructure it, comparecats need to end up looking like: ->[i]->{'services'}->[i]->{'nodes'}->[i]->{*}
  # not really restructuring; this just sorts all arrays, but doesn't take the node order into account.
  my $empty_node = {

  };

  foreach my $tmpcat (sort keys %$comparecatshash) {
    foreach my $tmpserv (sort keys %{$comparecatshash->{$tmpcat}->{'services'}}) {
      my @nodelist = map {defined $comparecatshash->{$tmpcat}->{'services'}->{$tmpserv}->{'nodes'}->{$_->{'name'}} ?
                        $comparecatshash->{$tmpcat}->{'services'}->{$tmpserv}->{'nodes'}->{$_->{'name'}} :
                        {
                          nodename => $_->{'name'},
                        }
                      } (@$groups);
      delete $comparecatshash->{$tmpcat}->{'services'}->{$tmpserv}->{'nodes'};
      $comparecatshash->{$tmpcat}->{'services'}->{$tmpserv}->{'nodes'} = \@nodelist;
    }
    my @servlist = map {$comparecatshash->{$tmpcat}->{'services'}->{$_}} sort keys %{$comparecatshash->{$tmpcat}->{'services'}};
    delete $comparecatshash->{$tmpcat}->{'services'};
    $comparecatshash->{$tmpcat}->{'services'} = \@servlist;
  }
  @$comparecats = map {$comparecatshash->{$_}} sort keys %$comparecatshash;
  return (1, $comparecats, $comparegroups);
}

# This is called both at group level, service level, and subservice level
sub munin_get_sorted_children {
    my $hash        = shift || return;

    my $children    = munin_get_children($hash);
    my $group_order;
    my $ret         = [];

    if (defined $hash->{'group_order'}) {
	$group_order = $hash->{'group_order'};
    } elsif (defined $hash->{'domain_order'}) {
	$group_order = $hash->{'domain_order'};
    } elsif (defined $hash->{'node_order'}) {
	$group_order = $hash->{'node_order'};
    } else {
    	$group_order = "";
    } 

    my %children = map {munin_get_node_name($_) => $_} @$children;

    foreach my $group (split /\s+/, $group_order) {
        if (defined $children{$group}) {
            push @$ret, $children{$group};
            delete $children{$group};
        }
        elsif ($group =~ /^(.+)=([^=]+)$/) {

            # "Borrow" the graph from another group
            my $groupname = $1;
            my $path      = $2;
            my $borrowed  = munin_get_node_partialpath($hash, $path);
            if (defined $borrowed) {
                munin_copy_node_toloc($borrowed, $hash, [$groupname]);
                $hash->{$groupname}->{'#%#origin'} = $borrowed;
            }
            push @$ret, $hash->{$groupname};
        }
    }

    foreach my $group (sort {$a cmp $b} keys %children) {
        push @$ret, $children{$group};
    }

    return $ret;
}

sub generate_service_templates {

    my $service = shift || return;

    return unless munin_get_bool($service, "graph", 1);

    my %srv;
    my $fieldnum = 0;
    my @graph_info;
    my @field_info;
    my @loc       = @{munin_get_picture_loc($service)};
    my $pathnodes = get_path_nodes($service);
    my $peers     = get_peer_nodes($service,
    lc munin_get($service, "graph_category", "other"));
    my $parent = munin_get_parent_name($service);
    my $filename = munin_get_html_filename($service);

    my $root_path = get_root_path($pathnodes);
    my $bp = borrowed_path($service) || ".";

    $srv{'node'} = munin_get_node_name($service);
    DEBUG "[DEBUG] processing service: $srv{node}";
    $srv{'service'}   = $service;
    $srv{"multigraph"}= munin_has_subservices($service);
    $srv{'label'}     = munin_get($service, "graph_title");
    $srv{'category'}  = lc(munin_get($service, "graph_category", "other"));
	$srv{'path'}      = $pathnodes;
	$srv{'peers'}     = $peers;
    $srv{'root_path'} = $root_path;
	$srv{'filename'}  = $filename;

    $srv{'url'} = "$srv{node}.html";

    my $path = join('/', @loc);

    my %imgs;
    $imgs{'imgday'}   = "$path-day.png";
    $imgs{'imgweek'}  = "$path-week.png";
    $imgs{'imgmonth'} = "$path-month.png";
    $imgs{'imgyear'}  = "$path-year.png";
    
    $imgs{'cimgday'}   = "$path-day.png";
    $imgs{'cimgweek'}  = "$path-week.png";
    $imgs{'cimgmonth'} = "$path-month.png";
    $imgs{'cimgyear'}  = "$path-year.png";
    
    if (munin_get_bool($service, "graph_sums", 0)) {
        $imgs{'imgweeksum'} = "$path-week-sum.png";
        $imgs{'imgyearsum'} = "$path-year-sum.png";
    }

    # dump all the png filename to a file
    my $fh = $config->{"#%#graphs_fh"};
    if ($fh) {
	    # values %imgs = the image file
	    # get them uniq, so we don't write them twice
	    my %paths = map { $_, 1 } (values %imgs);
	    foreach my $img (keys %paths) {
		print $fh "/" . $img . "\n";
	    }
    }

    my $imgpath = $root_path;
    if ( munin_get($config, "graph_strategy", "cron") eq "cgi" ) {
	$imgpath = $config->{'cgiurl_graph'};
    }

    map { $srv{$_} = $imgpath . "/" . $imgs{$_} } keys %imgs;

    # Compute the ZOOM urls
    {
        my $epoch_now = time;
	# The intervals are a bit larger, just like the munin-graph
	my $start_day = $epoch_now - (3600 * 30);
	my $start_week = $epoch_now - (3600 * 24 * 8);
	my $start_month = $epoch_now - (3600 * 24 * 33);
	my $start_year = $epoch_now - (3600 * 24 * 400);
	my $size_x = 800;
	my $size_y = 400;
	my $common_url = "$root_path/static/dynazoom.html?cgiurl_graph=$config->{'cgiurl_graph'}&amp;plugin_name=$path&amp;size_x=$size_x&amp;size_y=$size_y";
	$srv{zoomday} = "$common_url&amp;start_epoch=$start_day&amp;stop_epoch=$epoch_now";
	$srv{zoomweek} = "$common_url&amp;start_epoch=$start_week&amp;stop_epoch=$epoch_now";
	$srv{zoommonth} = "$common_url&amp;start_epoch=$start_month&amp;stop_epoch=$epoch_now";
	$srv{zoomyear} = "$common_url&amp;start_epoch=$start_year&amp;stop_epoch=$epoch_now";
    }

	for my $scale (@times) {
		my ($w, $h) = get_png_size(munin_get_picture_filename($service, $scale));
		if ($w && $h) {
			$srv{"img" . $scale . "width"}  = $w;
			$srv{"img" . $scale . "height"} = $h;
		}
	}

    if (munin_get_bool($service, "graph_sums", 0)) {
        $srv{imgweeksum} = "$srv{node}-week-sum.png";
        $srv{imgyearsum} = "$srv{node}-year-sum.png";

        for my $scale (["week", "year"]) {
		my ($w, $h) = get_png_size(munin_get_picture_filename($service, $scale, 1));
		if ($w && $h) {
			$srv{"img" . $scale . "sumwidth"}  = $w;
			$srv{"img" . $scale . "sumheight"} = $h;
		}
        }
    }

    # Do "help" section
    if (my $info = munin_get($service, "graph_info")) {
        my %graph_info;
        $graph_info{info} = $info;
        push @{$srv{graphinfo}}, \%graph_info;
    }

    #TODO move this ugly code to the templates
	$srv{fieldlist}
        .= "<tr><th align='left' valign='top'>Field</th><th align='left' valign='top'>Type</th><th align='left' valign='top'>Warn</th><th align='left' valign='top'>Crit</th><th></tr>";
    foreach my $f (@{munin_get_field_order($service)}) {
        $f =~ s/=(.*)$//;
        my $path = $1;
        next if (!defined $service->{$f});
        my $fieldobj = $service->{$f};
        next if (ref($fieldobj) ne "HASH" or !defined $fieldobj->{'label'});
        next if (!munin_draw_field($fieldobj));

        #DEBUG "DEBUG: single_value: Checking field \"$f\" ($path).";

        if (defined $path) {

            # This call is to make sure field settings are copied
            # for aliases, .stack, et al. Todo: put that part of
            # munin_get_rrd_filename into its own functino.
            munin_get_rrd_filename($f, $path);
        }

        my %field_info;
        $fieldnum++;

        $field_info{'hr'}    = 1 unless ($fieldnum % 3);
        $field_info{'field'} = $f;
        $field_info{'label'} = munin_get($fieldobj, "label", $f);
        $field_info{'type'}  = lc(munin_get($fieldobj, "type", "GAUGE"));
        $field_info{'warn'}  = munin_get($fieldobj, "warning");
        $field_info{'crit'}  = munin_get($fieldobj, "critical");
        $field_info{'info'}  = munin_get($fieldobj, "info");
        $field_info{'extinfo'} = munin_get($fieldobj, "extinfo");

        my $state = munin_field_status($fieldobj, $limits, 1);

        if (defined $state) {
            $field_info{'state_warning'}  = $state eq "warning" ? 1 : 0;
            $field_info{'state_critical'} = $state eq "critical" ? 1 : 0;
            $field_info{'state_unknown'}  = $state eq "unknown" ? 1 : 0;
        }
        push @{$srv{'fieldinfo'}}, \%field_info;
    }

    my $state = munin_service_status($service, $limits, 1);

    if (defined $state) {
        $srv{'state_warning'}  = $state eq "warning" ? 1 : 0;
        $srv{'state_critical'} = $state eq "critical" ? 1 : 0;
        $srv{'state_unknown'}  = $state eq "unknown" ? 1 : 0;
		push @{$problems->{"warnings"}}, \%srv if $state eq "warning";
		push @{$problems->{"criticals"}}, \%srv if $state eq "critical";
		push @{$problems->{"unknowns"}}, \%srv if $state eq "unknown";
    }

    return \%srv;
}

#TODO: move path specific information to html generation
sub get_path_nodes {
    my $hash = shift || return;
    my $ret  = [];
    my $link = $INDEX_FILENAME;

    unshift @$ret, {"pathname" => munin_get_node_name($hash), "path" => ""};
    while ($hash = munin_get_parent($hash)) {
        unshift @$ret, {"pathname" => munin_get_node_name($hash), "path" => $link};
        $link = "../" . $link;
    }

    $ret->[0]->{'pathname'} = undef;
    return $ret;
}

#TODO: This really needs some refactoring
sub get_peer_nodes {
    my $hash      = shift || return;
    my $category  = shift;
    my $ret       = [];
    my $parent    = munin_get_parent($hash) || return;
    my $me        = munin_get_node_name($hash);
    my $pchildren = munin_get_children($parent);

    my @peers = map { $_->[0] }
        sort { $a->[1] cmp $b->[1] }
        map { [ $_, munin_get_node_name($_) ] } @$pchildren;

    foreach my $peer (@peers) {
        next unless defined $peer and ref($peer) eq "HASH";
        next
          if defined $category
                and lc(munin_get($peer, "graph_category", "other")) ne
                  $category;
        next
          if (!defined $peer->{'graph_title'}
              and (!defined $peer->{'#%#visible'} or !$peer->{'#%#visible'}));
        next
          if (defined $peer->{'graph_title'}
            and !munin_get_bool($peer, "graph", 1));
        my $peername = munin_get_node_name($peer);
        next
          if $peername eq "contact"
            and munin_get_node_name($parent) eq "root";
        if ($peername eq $me) {
            unshift @$ret, {"name" => $peername, "link" => undef};
        }
        else {
            # Handle different directory levels between subgraphs and regular graphs
            if (munin_has_subservices ($hash)) {
                if (munin_has_subservices ($peer)) {
                    # I've got subgraphs, peer's got subgraphs
                    unshift @$ret,
                      {"name" => $peername, "link" => "../$peername/index.html"};
                } else { 
                    # I've got subgraphs, peer's a regular graph
                    unshift @$ret,
                      {"name" => $peername, "link" => "../$peername.html"};
                } 
            } elsif (munin_has_subservices ($peer)) {
                # I'm a regular graph, peer's got subgraphs
                unshift @$ret,
                  {"name" => $peername, "link" => "$peername/index.html"};
            } else {
                if (defined $peer->{'graph_title'}) {
                    # Both me and peer are regular graphs
                    unshift @$ret,
                      {"name" => $peername, "link" => "$peername.html"};
                }
                else {
                    # We're not on the graph level -- handle group peering
                    unshift @$ret,
                      {"name" => $peername, "link" => "../$peername/index.html"};
                }
            }
        }
    }
    return $ret;
}

#TODO: move url logic to html generation
sub get_root_path{
    my ($path) = @_;
    if ($path) {
        (my $root = $path->[0]->{'path'}) =~ s/\/index.html$//;
        return $root;
    }
    return "";
}

#TODO: move url logic to html generation
sub borrowed_path {
    # I wish I knew what this function does.  It appears to make
    # .. path elements to climb up the directory hierarchy.  To
    # "borrow" something from a different directory level.

    my $hash     = shift;
    my $prepath  = shift || "";
    my $postpath = shift || "";

    return unless defined $hash and ref($hash) eq "HASH";

    if (defined $hash->{'#%#origin'}) {
        return
	    $prepath . "../"
            . munin_get_node_name($hash->{'#%#origin'}) . "/"
            . $postpath;
    }
    else {
        if (defined $hash->{'#%#parent'}) {
            if (defined $hash->{'graph_title'}) {
                return borrowed_path($hash->{'#%#parent'}, $prepath . "../",
                    $postpath);
            }
            else {
                return borrowed_path(
                    $hash->{'#%#parent'},
                    $prepath . "../",
                    munin_get_node_name($hash) . "/" . $postpath
                );
            }
        }
        else {
            return;
        }
    }
}

#TODO: This method is obsolete when cgi-graphing is the only strategy left
sub get_png_size {
    my $filename = shift;
    my $width    = undef;
    my $height   = undef;

    return (undef, undef) if (munin_get($config, "graph_strategy", "cron") eq "cgi") ;

    if (open(my $PNG, '<', $filename)) {
        my $incoming;
        binmode($PNG);
        if (read($PNG, $incoming, 4)) {
            if ($incoming =~ /PNG$/) {
                if (read($PNG, $incoming, 12)) {
                    if (read($PNG, $incoming, 4)) {
                        $width = unpack("N", $incoming);
                        read($PNG, $incoming, 4);
                        $height = unpack("N", $incoming);
                    }
                }
            }
        }
        close($PNG);
    }

    return ($width, $height);
}



1;
