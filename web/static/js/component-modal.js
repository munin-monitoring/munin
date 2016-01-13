/**
 * Modal component
 */
(function($, window) {
	var Modal = function(modalId, modalHTMLContent, options) {
		this.modalId = modalId;
		this.modalHTMLContent = modalHTMLContent;
		this.options = options;

		this.prepare();

		return this;
	};

	Modal.prototype = {
		defaults: {
		},

		prepare: function() {
			this.settings = $.extend({}, this.defaults, this.options);
			var body = $('body'),
				that = this;

			// Create modal & append it to the body
			this.modal = $('<div />')
				.data('modalname', this.modalId)
				.addClass('modal')
				.css('display', 'none')
				.append(
					$('<div />')
						.addClass('title')
						.css('display', 'none')
						.append(
							$('<span />')
						)
						.append(
							$('<a />')
								.attr('href', '#')
								.addClass('action close')
								.append(
									$('<i />')
										.addClass('mdi mdi-window-close')
								)
						)
						.append(
							$('<a />')
								.attr('href', '#')
								.addClass('action open')
								.attr('id', 'modal' + this.modalId + '-option')
								.css('display', 'none')
								.append(
									$('<i />')
										.addClass('mdi mdi-open-in-new')
								)
						)
				)
				.append(this.modalHTMLContent)
				.appendTo(body);

			this.modalMask = $('<div />')
				.addClass('modalMask')
				.data('modalname', this.modalId)
				.css('display', 'none')
				.appendTo(body);

			// Register mask click event to hide the modal...
			this.modalMask.click(function() {
				that.hide();
			});
			// ... and also the modal title close button
			this.modal.find('.title > a.close').click(function(e) {
				e.preventDefault();
				that.hide();
			});

			return this;
		},

		setTitle: function(title) {
			var titleBar = this.modal.find('.title');
			titleBar.find('span').text(title);
			titleBar.show();
		},

		setOpenTarget: function(target) {
			var icon = this.modal.find('.open');
			icon.attr('href', target);
			icon.show();
		},

		show: function() {
			var that = this;

			// Show modal and mask
			this.modal.show();
			this.modalMask.show();

			// Reduce modal size if necessary
			this.adjustSize();

			// Register ESC keypress to hide the modal
			$(document).on('keyup.modal', function(e) {
				if (e.keyCode == 27)
					that.hide();
			});
		},

		hide: function() {
			// Hide modal and mask
			this.modal.hide();
			this.modalMask.hide();

			// Unregister ESC keypress event
			$(document).off('keyup.modal');
		},

		/**
		 * Reduce modal size if its width/height is wider than available space
		 */
		adjustSize: function() {
			var modalMaxWidth = 900;
			var modalMaxHeight = 630;

			this.modal.css('width', Math.min(modalMaxWidth, $(window).width()));
			this.modal.css('height', Math.min(modalMaxHeight), $(window).height());
		},

		getView: function() {
			return this.modal;
		}
	};

	Modal.defaults = Modal.prototype.defaults;

	window.Modal = Modal;
}(jQuery, window));
