/**
 * Graphs auto-refresh
 */

var graphsSelector = '.graph';

function startAutoRefresh(pGraphsSelector) {
	if (pGraphsSelector !== undefined)
		graphsSelector = pGraphsSelector;

	// Register on image load + error events to hide loading styles
	$(graphsSelector).on('load error', function() {
		setImageLoading($(this), false);
	});

	// Copy current src attribute as backup in an attribute
	$(graphsSelector).each(function() {
		$(this).attr('data-autorefresh-src', $(this).attr('src'));
	});

	setInterval(refreshGraphs, 5*60*1000);
}

/**
 * Tells UI that this specific image is loading (or not)
 *  (lowers opacity and shows loading spinner)
 */
function setImageLoading(imgDomElement, isLoading) {
	if (isLoading) {
		imgDomElement.parent().css('opacity', '0.7');
		imgDomElement.parent().find('.graph_loading').show();
	} else {
		imgDomElement.parent().css('opacity', '1');
		imgDomElement.parent().find('.graph_loading').hide();
	}
}

/**
 * Refresh every graph in this page
 */
function refreshGraphs() {
	$(graphsSelector).each(function() {
		var src = $(this).attr('data-autorefresh-src');

		// Add new timestamp
		var prefix = src.indexOf('?') != -1 ? '&' : '?';
		src += prefix + new Date().getTime();

		setImageLoading($(this), true);

		// Since we change the src attr, we have to reattach
		// the error event
		$(this).on('error', function() {
			setImageLoading($(this), false);
		});

		$(this).attr('src', src);
	});
}
