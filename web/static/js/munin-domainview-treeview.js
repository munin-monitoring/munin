/**
 * Domainview treeview
 */

$(document).ready(function() {
	// Init treeview
	var toggles = $('.toggle');

	// All toggles are expanded
	toggles.attr('data-expanded', 'true');

	// Attach toggle event
	toggles.click(function() {
		if ($(this).attr('data-expanded') == 'true') {
			// Reduce it
			$(this).parent().next().hide();

			$(this).attr('data-expanded', 'false');
		} else {
			// Expand it
			$(this).parent().next().show();

			$(this).attr('data-expanded', 'true');
		}
	});
});
