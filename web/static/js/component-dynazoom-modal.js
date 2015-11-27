/**
 * Adds a dynazoom icon on each graph. On click, displays a modal with the dynazoom page as content
 */

$(document).ready(function() {
	var body = $('body');
	if (body.width < 768) // Dynazoom isn't convenient on too small devices
		return;

	var graphs = $('.graph'),
		MODAL_ID = 'dynazoomModal';

	graphs.after('<i class="fa fa-expand dynazoomModalLink"></i>');

	// Prepare a hidden modal
	var modal = prepareModal(MODAL_ID, '<iframe frameBorder="0" seamless="seamless"></iframe>');
	var dynazoomIframe = modal.find('iframe');

	// Bind onclick event
	$('.dynazoomModalLink').click(function(e) {
		e.preventDefault();

		var img = $(this).parent().find('img.graph');

		// Create dynazoom URL
		// Expected plugin_name var is group_name/host/plugin
		// This can be retrieved easily from img src (/group_name/host/plugin.png?...)
		var plugin_name = img.attr('src').substring(1); // Remove leading '/';
		plugin_name = plugin_name.substr(0, plugin_name.lastIndexOf('-')); // Remove everything after -(day/week/...)

		// Set start_epoch depending on graph time range (leave stop_epoch default)
		// Get "day/month/..." from img src
		var src = img.attr('src');
		var timeRange = src.substr(src.lastIndexOf('-')+1); // Remove everything before -(day/week/...)
		timeRange = timeRange.substr(0, timeRange.indexOf('.png')); // Remove .png?...

		var start_epoch = Math.round(new Date().getTime()/1000);
		switch (timeRange) {
			case 'hour':
				start_epoch -= 3600; break;
			case 'day':
				start_epoch -= 3600 * 30; break;
			case 'week':
				start_epoch -= 3600 * 24 * 8; break;
			case 'month':
				start_epoch -= 3600 * 24 * 33; break;
			case 'year':
				start_epoch -= 3600 * 24 * 400; break;
			default:
				start_epoch = -1; break;
		}

		var dzQS = new Querystring('');
		dzQS.set('cgiurl_graph', '/');
		dzQS.set('plugin_name', plugin_name);
		if (start_epoch != -1)
			dzQS.set('start_epoch', start_epoch);
		dzQS.set('content_only', 1);
		dzQS.set('size_x', 700);
		dzQS.set('size_y', 350);

		var url = '/dynazoom.html?' + $.param(dzQS.params);
		dynazoomIframe.attr('src', url);
		setModalTitle(MODAL_ID, 'Dynazoom - ' + img.attr('alt'));

		// Add "open" button to modal
		// We have to set back content_only to 0 (false)
		dzQS.set('content_only', 0);
		var openUrl = '/dynazoom.html?' + $.param(dzQS.params);
		setModalOpenTarget(MODAL_ID, openUrl);
		showModal(MODAL_ID);
	});
});
