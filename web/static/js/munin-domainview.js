/**
 * Domainview specific javascript
 */
$(document).ready(function() {
	var treeviewRoot = $('.treeview-root'),
		treeview = treeviewRoot.treeview();

	// Init treeview
	treeview.expandAll();
	$('#reduce-all').click(function() {
		treeview.reduceAll();
	});
	$('#expand-all').click(function() {
		treeview.expandAll();
	});


	window.toolbar.prepareFilter('Filter plugins', function(val) {
		if (val == '') {
			// Empty filter: display everything
			$('#content').find('> ul').find('*').show();
			return;
		}

		// Treeview
		treeview.expandAll();

		// Loop on each plugin ("service")
		$('.service').find('a').each(function() {
			var pluginName = $(this).text();
			var href = $(this).attr('href');
			var pluginId = '';
			if (href.charAt(href.length-1) == '/') {
				// /diskstats_latency/
				href = href.substr(0, href.length-1);
				pluginId = href.substr(href.lastIndexOf('/')+1);
			} else {
				// df_inode.html
				pluginId = href.substr(href.lastIndexOf('/')+1, href.lastIndexOf('.')-href.lastIndexOf('/')-1);
			}

			if (window.toolbar.filterMatches(val, pluginName) || window.toolbar.filterMatches(val, pluginId))
				$(this).parent().parent().show();
			else
				$(this).parent().parent().hide();
		});

		// Hide categories names
		//  (can't use :visible since parent may be hidden)
		$('.host').each(function() {
			if ($(this).next().children().filter(function() {
					return $(this).css('display') != 'none';
				}).length == 0)
				$(this).parent().hide();
			else
				$(this).parent().show();
		});

		// Hide domains names
		//  (can't use :visible since parent may be hidden)
		$('.domain').each(function() {
			if ($(this).next().children().filter(function() {
					return $(this).css('display') != 'none';
				}).length == 0)
				$(this).parent().hide();
			else
				$(this).parent().show();
		});
	});

	// Switch node on header
	$('.switchable[data-switch="header"]').list('header', {
		list: $('.switchable_content[data-switch="header"]')
	});

	// Assign tab-indexes to elements
	treeviewRoot.find('a').each(function(index) {
		$(this).attr('tabindex', index+1);
	});
	removeTabIndexOutline();
});
