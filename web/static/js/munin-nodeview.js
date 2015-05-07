/**
 * Javascript executed on munin-nodeview page
 */

var content,
	graphs,
	h4s,
	tabs;

$(document).ready(function() {
	content = $('#content');
	graphs = $('.graph');
	h4s = $('h4');
	tabs = $('.tabs').find('li');

	// Append a loading <img> on each graph img
	graphs.after('<img src="/static/img/loading.gif" class="graph_loading" style="display:none" />');

	// Auto-refresh
	startAutoRefresh();

	// Prepare filter
	prepareFilter('Filter graphs', function(val) {
		if (val.length == 0)
			showTabs();
		else
			hideTabs();

		graphs.each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (filterMatches(val, pluginName) || filterMatches(val, pluginId)) {
				$(this).parent().show();
				// Show plugin name
				h4s.filter(function() {
					return $(this).text() == pluginName;
				}).show();

				// Show next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().show();
			}
			else {
				$(this).parent().hide();
				// Hide plugin name
				h4s.filter(function() {
					return $(this).text() == pluginName;
				}).hide();

				// Hide next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().hide();
			}
		});

		// If tabs aren't enabled, they are used as anchors links
		if (content.attr('data-tabsenabled') == 'false') {
			tabs.each(function() {
				if (filterMatches(val, $(this).text()))
					$(this).show();
				else
					$(this).hide();
			});
		}

		// Hide unneccary categories names
		$('div[data-category]').each(function() {
			if ($(this).children(':visible').length == 0)
				$(this).prev().hide();
			else
				$(this).prev().show();
		});

		if (val.length == 0) {
			// Remove display CSS property to category names (h3)
			// to let tabs decide if they should be shown or not
			$('h3').css('display', '');
		}
	});


	// Back to top button
	var backToTop = $('#backToTop');
	var offset = 300;

	$(window).scroll(function() {
		if ($(this).scrollTop() > offset)
			backToTop.addClass('visible');
		else
			backToTop.removeClass('visible');
	});

	backToTop.click(function(e) {
		e.preventDefault();
		$('body, html').animate({
			scrollTop: 0
		}, 500);
	});

	// Node switch
	prepareSwitchable('header');
});
