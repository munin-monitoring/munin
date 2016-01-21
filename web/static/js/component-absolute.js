/**
 * Absolute-positioned elements:
 *   * absolute
 *     * toolbar
 *     * list
 */

(function($, window) {

	// Define Absolute
	var Absolute = function() { };

	Absolute.prototype = {
		/**
		 * Shows the absolute element. Its position is computed from trigger element
		 */
		showElement: function(trigger, animate) {
			var that = this;

			if (this.element.is(':visible')) {
				this.element.hide();
				return;
			}

			// Generate left & top element position
			var triggerBottom = trigger.position().top + trigger.outerHeight(true);
			this.element.css('top', triggerBottom);

			var left = trigger.position().left + trigger.outerHeight() / 2;
			this.element.css('left', left);

			// Check if element is out of view
			this.element.show(); // So we can get its position & dimensions
			var delta = $(window).width() - (this.element.position().left + this.element.outerWidth());
			if (delta < 0)
				this.element.css('left', left - (Math.abs(delta) + 5));
			this.element.hide();

			// When clicking outside, hide it
			$(document).bind('mouseup.absolute', function(e) {
				if (!that.element.is(e.target) // If we're neither clicking on element
					&& that.element.has(e.target).length === 0
					&& !trigger.is(e.target) // nor on trigger
					&& that.element.has(e.target).length === 0) { // nor on a descendent
					that.hideElement(animate);

					// Unbind this event
					$(document).unbind('click.absolute');
				}
			});

			// Display element
			if (animate)
				this.element.fadeIn(100);
			else
				this.element.show();
		},

		hideElement: function(animate) {
			if (animate)
				this.element.fadeOut(100);
			else
				this.element.hide();
		}
	};


	// Define Tooltip
	var Tooltip = function(elem, message, options) {
		Absolute.call(this);
		this.trigger = elem;
		this.$trigger = $(elem);
		this.message = message;
		this.options = options;
		this.metadata = this.$trigger.data('tooltip-options');
	};

	Tooltip.prototype = new Absolute();
	Tooltip.prototype.constructor = Tooltip;

	// Extend Absolute's prototype
	Tooltip.prototype.defaults = {
		/** If true, <sup>?</sup> will be added to trigger */
		appendQuestionMark: false,
		/** Tooltip fixed width */
		width: 'auto',
		/** If true, inner text won't wrap */
		singleLine: false
	};

	Tooltip.prototype.init = function() {
		var that = this;
		this.settings = $.extend({}, this.defaults, this.options, this.metadata);

		// Create tooltip & append it to body
		this.element = $('<div />')
			.addClass('tooltip')
			.css('width', this.settings.width)
			.html(this.message)
			.appendTo($('body'));

		if (this.settings.singleLine)
			this.element.addClass('singleLine');

		// Append <sup>?</sup> to trigger
		if (this.settings.appendQuestionMark)
			this.$trigger.html(this.$trigger.text() + '<sup>?</sup>');

		// Register mouseenter event
		this.$trigger.mouseenter(function() {
			that.showElement(that.$trigger, true);
		});

		// Register mouseleave event
		this.$trigger.mouseleave(function() {
			that.hideElement(that.$trigger, true);
		});

		return this;
	};

	Tooltip.defaults = Tooltip.prototype.defaults;

	$.fn.tooltip = function(message, options) {
		return this.each(function() {
			new Tooltip(this, message, options).init();
		});
	};


	// Define List
	/**
	 * Shows an absolute-positioned list on trigger click.
	 */
	var List = function(elem, name, options) {
		Absolute.call(this);
		this.trigger = elem;
		this.$trigger = $(elem);
		this.name = name;
		this.options = options;
		this.metadata = this.$trigger.data('list-options');
	};

	List.prototype = new Absolute();
	List.prototype.constructor = List;

	// Extend Absolute's prototype
	List.prototype.defaults = {
		width: 'auto',

		// If null, will be created
		list: null,

		// Specifis options when content: null
		list_options: {
			title: null
		}
	};

	List.prototype.init = function() {
		var that = this;
		this.settings = $.extend({}, this.defaults, this.options, this.metadata);

		var trigger = this.$trigger;

		// List
		if (this.settings.list == null) {
			this.settings.list = $('<div />')
				.addClass('switchable_content')
				.data('name', that.name)
				.appendTo($('body'));

			// If title provided, add it
			if (this.settings.list_options.title != null) {
				this.settings.list.append(
					$('<div />')
						.addClass('title')
						.text(this.settings.list_options.title)
				);
			}
		} else {
			// Gray out current element in list
			this.settings.list.children().filter(function() {
				return $.trim(trigger.text()) == $.trim($(this).text());
			}).addClass('current');
		}

		this.element = this.settings.list;
		this.element.css('width', this.settings.width);

		// Register event
		trigger.click(function() {
			that.showElement(trigger, false);
		});

		return this;
	};

	List.prototype.addItem = function(icon, name, callback) {
		var that = this;

		return $('<a />')
			.attr('href', '#')
			.text(name)
			.prepend(
				$('<i />')
					.addClass('mdi ' + icon)
			)
			.click(function(e) { // Close list
				e.preventDefault();
				that.hideElement(false);
			})
			.click(callback) // Execute callback
			.appendTo(this.element);
	};

	List.defaults = List.prototype.defaults;

	$.fn.list = function(name, options) {
		return new List(this.first(), name, options).init();
	};

	window.List = List;
}(jQuery, window));
