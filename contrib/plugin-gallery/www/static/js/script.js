/**
 * Gallery basic script
 */

$(document).ready(function() {
	// Intercept documentation docs links click
	var MODAL_ID = 'doc_modal';
	var modal = prepareModal(MODAL_ID, '<iframe frameBorder="0" seamless="seamless"></iframe>');
	var iframe = modal.find('iframe');

	// Register load event on iframe to inject CSS
	iframe.load(function() {
		iframe.contents().find('head').append('<link rel="stylesheet" href="/static/css/style-doc.css" />');
	});

	$('span.host').find('a[title="Info"]').click(function(e) {
		// Don't open the link
		e.preventDefault();

		iframe.attr('src', $(this).attr('href'));

		// Show modal
		setModalTitle(MODAL_ID, 'Documentation - ' + $(this).text());

		// Add "open" button to modal
		setModalOpenTarget(MODAL_ID, $(this).attr('href'));
		showModal(MODAL_ID);
	});
});

/**
 * Prepares a modal to be shown later
 */
function prepareModal(modalId, modalHTMLContent) {
	var body = $('body');
	body.append('<div class="modal" data-modalname="' + modalId + '" style="display: none;">'
		+ '<div class="title" style="display:none">'
		+ '    <span></span>'
		+ '    <a href="#close" class="action close"></a>'
		+ '    <a href="#" class="action open" id="modal' + modalId + '-open" style="display: none;"></a>'
		+ '</div>'
		+ modalHTMLContent
		+ '</div>');
	body.append('<div class="modalMask" data-modalname="' + modalId + '" style="display: none;"></div>');

	var modal = $('.modal[data-modalname=' + modalId + ']');

	// Register mask click event to hide the modal...
	$('.modalMask[data-modalname=' + modalId + ']').click(function() {
		hideModal(modalId);
	});
	// ... and also the modal title close button
	modal.find('.title > a.close').click(function(e) {
		e.preventDefault();
		hideModal(modalId);
	});

	return modal;
}

function setModalTitle(modalId, modalTitle) {
	var titleBar = $('[data-modalname=' + modalId + ']').find('.title');
	titleBar.find('span').text(modalTitle);
	titleBar.show();
}

function setModalOpenTarget(modalId, modalTitleOpenTarget) {
	var openLink = $('[data-modalname=' + modalId + ']').find('.open');
	openLink.attr('href', modalTitleOpenTarget);
	openLink.show();
}

function showModal(modalId) {
	// Show modal and mask
	$('[data-modalname=' + modalId + ']').show();

	// Reduce modal size if necessary
	adjustModalSize(modalId);

	// Register ESC keypress to hide the modal
	$(document).on('keyup.modal', function(e) {
		if (e.keyCode == 27)
			hideModal(modalId);
	});
}

/**
 * Reduce modal size if its width/height is wider than available space
 * @param modalId
 */
function adjustModalSize(modalId) {
	var modalMaxWidth = 900;
	var modalMaxHeight = 630;

	var modal = $('.modal[data-modalname=' + modalId + ']');
	modal.css('width', Math.min(modalMaxWidth, $(window).width()));
	modal.css('height', Math.min(modalMaxHeight), $(window).height());
}

function hideModal(modalId) {
	// Hide modal and mask
	$('[data-modalname=' + modalId + ']').hide();

	// Unregister ESC keypress event
	$(document).off('keyup.modal');
}
