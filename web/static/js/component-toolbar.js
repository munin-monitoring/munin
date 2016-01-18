/**
 * Toolbar & navigation panel jQuery component
 */
(function($) {
	var Toolbar = function(elem, options) {
		this.elem = $(elem);
		this.options = options;
		this.metadata = this.elem.data('toolbar-options');
	};

	Toolbar.prototype = {
		defaults: {
			mobileTriggerWidth: 768
		},

		init: function() {
			var that = this;
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			// Init component
			this.filterWrap = this.elem.find('.filter');
			this.actions = this.elem.find('.right').find('.actions');
			this.navigation = $('nav');
			this.navigationMask = $('.navigation-mask').click(function() {
				that.toggleNavigation(false, true);
			});

			this.elem.find('#navigation-toggle').click(function() {
				var makeVisible = that.navigation.width() <= 0;
				that.toggleNavigation(makeVisible, true);
			});

			return this;
		},

		/**
		 * Called by each page to setup header filter
		 * @param placeholder Input placeholder
		 * @param onFilterChange Called each time the input text changes
		 */
		prepareFilter: function(placeholder, onFilterChange) {
			// Toggle filter container visibility
			this.filterWrap.show();

			var input = this.filterWrap.find('#filter'),
				cancel = this.filterWrap.find('#cancelFilter');

			// Set placeholder
			input.attr('placeholder', placeholder);

			// Create a delay function to avoid triggering filter on each keypress
			var delay = (function(){
				var timer = 0;
				return function(callback, ms){
					clearTimeout(timer);
					timer = setTimeout(callback, ms);
				};
			})();

			var updateFilterInURL = function() {
				// Put the filter query in the URL (to keep it when refreshing the page)
				var query = input.val();

				saveState('filter', query);
			};

			input.on('keyup', function() {
				var val = $(this).val();

				delay(function() {
					if (val != '')
						cancel.show();
					else
						cancel.hide();

					// Call onFilterChange
					onFilterChange(val);
					updateFilterInURL();
				}, 200);
			});

			cancel.click(function() {
				input.val('');
				$(this).hide();
				onFilterChange('');
				updateFilterInURL();
			});

			// Register ESC key: same action as cancel filter
			$(document).keyup(function(e) {
				if (e.keyCode == 27 && input.is(':focus') && input.val().length > 0)
					cancel.click();
			});

			// There may be a 'filter' GET parameter in URL: let's apply it
			var qs = new Querystring();
			if (qs.contains('filter')) {
				input.val(qs.get('filter'));
				// Manually trigger the keyUp event on filter input
				input.keyup();
			}
		},

		/**
		 * Transforms a string to weaken filter
		 * 	(= get more filter results)
		 * @param filterExpr
		 */
		sanitizeFilter: function(filterExpr) {
			return $.trim(filterExpr.toLowerCase());
		},

		/**
		 * Returns true whenever a result matches the filter expression
		 * @param filterExpr User-typed expression
		 * @param result Candidate
		 */
		filterMatches: function(filterExpr, result) {
			return this.sanitizeFilter(result).indexOf(this.sanitizeFilter(filterExpr)) != -1;
		},

		/**
		 * Adds an action icon to the toolbar
		 * @param icon Icon class (mdi-refresh)
		 * @param text Action name
		 * @param overflow boolean: if true, will be added to the overflow
		 * @param callback
		 */
		addActionIcon: function(icon, text, overflow, callback) {
			var body = $('body');

			// Force overflow on mobiles
			if (body.width() < 768)
				overflow = true;

			if (overflow) {
				// Add overflow button if it doesn't exist yet
				if (!this.elem.find('.overflow').length) {
					// Create overflow button
					var overflowButton = $('<div />')
						.addClass('action-icon overflow')
						.click(null)
						.append(
							$('<i />').addClass('mdi mdi-dots-vertical')
						)
						.appendTo(this.actions);

					// Create list
					var list = overflowButton.list('overflow');

					// Add item to list
					list.addItem(icon, text, callback);
				}
			} else {
				var button = $('<div />')
					.addClass('action-icon')
					.click(callback)
					.append(
						$('<i />').addClass('mdi ' + icon)
					)
					.prependTo(this.actions);

				// Tooltip for text
				button.tooltip(text, {
					singleLine: true
				});
			}
		},

		toggleNavigation: function(visible, animate) {
			var destWidth = visible ? 200 : 0;

			if (animate) {
				this.navigation.animate({
					width: destWidth + 'px'
				}, 200);
			} else {
				this.navigation.css('width', destWidth);
			}

			// Toggle navigation mask if necessary
			if ($(document).width() < this.settings.mobileTriggerWidth) {
				if (visible)
					this.navigationMask.fadeIn(150);
				else
					this.navigationMask.fadeOut(150);
			}
		}
	};

	Toolbar.defaults = Toolbar.prototype.defaults;

	$.fn.toolbar = function(options) {
		return new Toolbar(this.first(), options).init();
	};

	window.Toolbar = Toolbar;
}(jQuery));
