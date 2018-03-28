#!/bin/sh
#
# This script builds a HTML presentation of the perldocs
# integrated in the Munin plugins collected at github
# so that users can browse info about available plugins.
#
# Plugin authors shall contribute example graphs
# for their plugins also. Rules are defined here:
# http://munin-monitoring.org/wiki/PluginGallery
#
# Copyright 2014-2018 Gabriele Pohl <contact@dipohl.de>
# Copyright 2018 Lars Kruse <devel@sumpfralle.de>
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE as published
# by the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# You should have received a copy of the GNU AFFERO GENERAL PUBLIC LICENSE
# (for example COPYING); If not, see <http://www.gnu.org/licenses/>.


set -eu

if [ $# -ne 1 ]; then
	echo "Syntax:  $(basename "$0")  HTML_EXPORT_DIR"
	echo
	echo "BEWARE: all extra files in this directory will be deleted"
fi >&2

# DocumentRoot of the Gallery (published directly via a webserver)
# BEWARE: the previous content of this directory is deleted
TARGET_DIR=$(realpath "$1")

# This directory is for files only needed to build the Gallery
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# List of files or directories to be cleaned up on exit. Simply add more items to the variable.
TMP_PATH_REMOVAL_LIST=""
trap 'if [ -n "$TMP_PATH_REMOVAL_LIST" ]; then rm -rf $TMP_PATH_REMOVAL_LIST; fi' EXIT


# Download a compressed tar archive from a remote location and extract it into a target directory.
extract_plugins() {
	local source_url="$1"
	local plugin_target_dir="$2"
	mkdir -p "$plugin_target_dir"
	wget --quiet --output-document=- "$source_url" \
		| tar -xz -C "$plugin_target_dir" --wildcards --strip-components=2 --anchored --no-wildcards-match-slash "*/plugins"
}


# Retrieve the human-readable description for a category name.
# The output is empty for an unknown category.
get_category_description() {
	local category="$1"
	echo "$category" | awk -f "$SCRIPT_DIR/well-known-categories.incl" -e '{ print arr[$1]; }'
}


# Generate html export files for all plugins within a repository.
build_target_dir() {
	local plugin_dir="$1"
	local target_dir="$2"
	# URL path (must start and end with a slash)
	local publish_path="$3"
	local collection_name="$4"
	local plugins_source_url="$5"
	local intro_file="$6"
	local categories_and_plugins
	local plugins_with_category
	local plugins_without_categories
	local prep_index_file
	local prep_category_navigation_file
	local build_log

	prep_category_navigation_file=$(mktemp)
	TMP_PATH_REMOVAL_LIST="$TMP_PATH_REMOVAL_LIST $prep_category_navigation_file"
	prep_index_file=$(mktemp)
	TMP_PATH_REMOVAL_LIST="$TMP_PATH_REMOVAL_LIST $prep_index_file"

	cd "$plugin_dir"
	mkdir -p "$target_dir"
	# Find relation between plugins and categories
	# Result: space-separated list of category and plugin_filename sorted by category
	# The plugin names need to start with their top level directory ("./" is removed).
	# Plugins are executable or end with ".in" (for stable-2.0).
	categories_and_plugins=$(find . -type f "(" -executable -o -name "*.in" ")" -print0 \
		| xargs -0 grep -i --exclude-from="$SCRIPT_DIR/grep-files.excl" -E \
			"(category|Munin::Plugin::Pgsql)" \
		| sort \
		| grep -v "^$" \
		| sed 's#^\./##' \
		| awk -F ":" -f "$SCRIPT_DIR/split-greplist.awk" \
		| LC_COLLATE=C sort | uniq)

	plugins_with_category=$(echo "$categories_and_plugins" | cut -f 2- -d " " | sort | uniq)

	# Find the plugins that do not belong to any category
	# Use the dummy operation "grep --exclude-from=? ." for filtering unwanted files.
	plugins_without_categories=$(find . -type f "(" -executable -o -name "*.in" ")" -print0 \
		| xargs -0 grep -l --exclude-from="$SCRIPT_DIR/grep-files.excl" . \
		| grep -vF "/node.d.debug/" \
		| sort \
		| grep -v "^$" \
		| sed 's#^\./##' \
		| while read -r fname; do
			echo "$plugins_with_category" | cut -f 2 -d " " \
				| grep -qxF "$fname" || echo "$fname"; done)

	# combine the list of explicitly categorized plugins with the implicit list of "other"
	# Use "--version-sort" for proper sorting of "node.d.*/*" files (in master). Otherwise
	# the "sub categories" (based on parent directory names) are interleaved.
	categories_and_plugins_with_other=$(
		{
			echo "$categories_and_plugins";
			echo "$plugins_without_categories" | sed 's/^/other /';
		} | sort --version-sort | uniq)
	printf "%d plugins without category were assigned to category 'other'\n" \
		"$(echo "$categories_and_plugins_with_other" | grep -c "^other ")"

	# Create the html snippet for category navigation.
	echo "$categories_and_plugins_with_other" | cut -f 1 -d " " | sort | uniq -c | grep -v "^$" \
			| while read -r count category; do
		printf '\t\t<li><a href="%s-index.html" title="%s">%s (%d)</a></li>\n' \
				"$category" "$(get_category_description "$category")" \
				"$category" "$count"
		done >"$prep_category_navigation_file"

	# Compile template for category pages
	cat "$SCRIPT_DIR/static/gallery-header.html" \
		"$SCRIPT_DIR/static/gallery-cat-header.html" \
		"$prep_category_navigation_file" \
		"$SCRIPT_DIR/static/gallery-cat-footer.html" \
		>"$prep_index_file"

	# Create entry page
	mkdir -p "$target_dir$publish_path"
	cat "$SCRIPT_DIR/static/gallery-header.html" \
		"$SCRIPT_DIR/static/gallery-cat-header.html" \
		"$prep_category_navigation_file" \
		"$SCRIPT_DIR/static/gallery-cat-footer.html" \
		"$SCRIPT_DIR/static/$intro_file" \
		"$SCRIPT_DIR/static/gallery-footer.html" \
		>"$target_dir${publish_path}index.html"

	# Create Gallery pages for all categories that were explicitly set in the plugin script files
	build_log=$(echo "$categories_and_plugins_with_other" | grep -v "^$" \
		| awk -f "$SCRIPT_DIR/well-known-categories.incl" \
			-f "$SCRIPT_DIR/print-gallery.awk" \
			-v "static_dir=$SCRIPT_DIR/static" \
			-v "target_dir=$target_dir" \
			-v "plugin_dir=$plugin_dir" \
			-v "collection_name=$collection_name" \
			-v "publish_path=$publish_path" \
			-v "plugins_source_url=$plugins_source_url" \
			-v "prep_index_file=$prep_index_file")
	printf "%d times created perldoc pages with content\n" \
		"$(echo "$build_log" | grep -c "output saved")"
	printf "%d times no perldoc content found\n" \
		"$(echo "$build_log" | grep -c "No documentation")"
}


# Copy example graph files and add references to the existing html files.
publish_example_graphs() {
	local plugin_dir="$1"
	local target_dir="$2"
	local example_graph_files
	local graph_log
	local graph_errors

	cd "$plugin_dir"
	mkdir -p "$target_dir"

	# Collect example graphs
	example_graph_files=$(find . -type f -name "*.png" | grep -vF "/node.d.debug/" | sort)

	# Include example graphs in perldoc pages
	graph_log=$(echo "$example_graph_files" | grep -v "^$" \
		| awk -f "$SCRIPT_DIR/include-graphs.awk" -v "target_dir=$target_dir")
	# copy images
	echo "$example_graph_files" | while read -r fname; do
		mkdir -p "$target_dir/$(dirname "$fname")"
		cp "$fname" "$target_dir/$fname"
	done
	printf "%d example graph images illustrate the plugin pages\n" "$(echo "$graph_log" | grep -c "^Plugin:")"
	# show all errors
	graph_errors=$(echo "$graph_log" | grep -v "^Plugin:" || true)
	if [ -n "$graph_errors" ]; then
		echo "$graph_errors" | sed 's/^/ERROR: /'
		global_exitcode=1
	fi
}


# Publish the gallery data for a specific branch.
publish_branch() {
	local repo="$1"
	local branch="$2"
	local publish_path="$3"
	local collection_name="$4"
	local target_dir="$5"
	local intro_file="$6"
	local plugin_dir

	plugin_dir=$(mktemp -d)
	TMP_PATH_REMOVAL_LIST="$TMP_PATH_REMOVAL_LIST $plugin_dir"

	echo "************ $collection_name: $repo / $branch -> $publish_path ************"
	echo "... retrieving a fresh archive from github repository ..."
	extract_plugins "https://github.com/munin-monitoring/$repo/archive/$branch.tar.gz" "$plugin_dir"

	echo "... start building the new gallery pages ..."
	build_target_dir "$plugin_dir" "$target_dir" "$publish_path" "$collection_name" \
		"https://raw.githubusercontent.com/munin-monitoring/$repo/$branch/plugins" \
		"$intro_file"

	echo "... publishing example graphs ..."
	publish_example_graphs "$plugin_dir" "$target_dir$publish_path"

	# fix permissions of fresh html files (they are created with 600)
	find "$target_dir" -type f -name "*.html" -print0 | \
		xargs --null --no-run-if-empty chmod 644
	chmod 755 "$target_dir"
}


# Directory within DocumentRoot to store pages and images about the plugins
work_dir=$(mktemp -d)
TMP_PATH_REMOVAL_LIST="$TMP_PATH_REMOVAL_LIST $work_dir"


# override this value anywhere if a non-zero exitcode of the script is suitable
global_exitcode=0

if ! perldoc -V >/dev/null; then
	echo >&2 "ERROR: Missing 'perldoc' for gallery build"
	exit 1
fi

publish_branch "munin"   "stable-2.0" "/"         "Core - 2.x"     "$work_dir" "gallery-intro.html"
publish_branch "munin"   "master"     "/devel/"   "Core - pre 3.0" "$work_dir" "gallery-intro.html"
publish_branch "contrib" "master"     "/contrib/" "3rd-Party"      "$work_dir" "gallery-intro-contrib.html"
rsync -ax --delete "$SCRIPT_DIR/www/static" "$work_dir/" "$TARGET_DIR/"

# maybe exit with error (e.g. useful for running via 'chronic')
exit "$global_exitcode"
