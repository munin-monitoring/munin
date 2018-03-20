/**
 * Nodeview/comparison tabs
 *  Tabs can be disabled by setting the <div id="content"> tabsenabled attribute to false
 */

(function($, window) {
	var Tabs = function(elem, options) {
		this.elem = elem;
		this.$elem = $(elem);
		this.options = options;
		this.metadata = this.$elem.data('tabs-options');
	};

	Tabs.prototype = {
		defaults: { },

		init: function() {
			var that = this;
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			// Init component
			this.content = $('#content');
			this.tabsEnabled = this.content.attr('data-tabsenabled') == 'true';
			this.tabsContainer = $('.tabs');
			this.tabs = this.tabsContainer.find('li');
			this.categoryTitles = $('h3');

			// Get active tab
			var qs = new Querystring();
			if (qs.contains('cat'))
				this.activeTab = this.tabs.filter(function() { return $.trim($(this).text()) == qs.get('cat'); });
			else if (window.location.hash.length > 0) { // URL contains anchor to category: overview->nodeview
				var anchorName = window.location.hash.substr(1); // Remove leading #
				this.activeTab = this.tabs.filter(function() { return $.trim($(this).text()) == anchorName; });
			}
			else
				this.activeTab = this.tabs.first();

			// If category in URL doesn't exist
			if (this.activeTab[0] === undefined)
				this.activeTab = this.tabs.first();


			// If tabs are disabled, they will serve as links to jump to categories
			if (!this.tabsEnabled) {
				// Remove "ALL" tab
				this.tabs.first().remove();

				this.tabs.each(function() {
					var text = $(this).text();
					$(this).html('<a href="#' + text + '">' + text + '</a>');
				});

				// Stop here
				return this;
			}

			this.activeTab.addClass('active');

			// Register tab click/enter listener
			this.tabs.click(function() { // click
				that.goTo($(this));
			}).keyup(function(e) { // <Enter>
				if (e.keyCode === 13)
					that.goTo($(this));
			});

			// Hide graphs that aren't in the activeTab category
			if (this.activeTab.index() != 0) {
				// Hide all categories
				$('[data-category]').hide();
				// Show the right one
				$('[data-category="' + this.activeTab.text() + '"]').show();

				this.categoryTitles.hide();
			}
			else { // All
				$('[data-category]').show();

				this.categoryTitles.show();
			}

			// If there's an active filter, hide tabs
			if (qs.contains('filter'))
				this.hideTabs();
			else
				this.showTabs();

			return this;
		},

		/**
		 * Switches to a specific tab
		 * @param tab DOM element
		 */
		goTo: function(tab) {
			this.activeTab.removeClass('active');
			this.activeTab = tab;
			this.activeTab.addClass('active');

			// Hide all categories
			if (tab.index() != 0) {
				$('[data-category]').hide();
				// Show the right one
				$('[data-category="' + this.activeTab.text() + '"]').show();

				this.categoryTitles.hide();
			}
			else { // ALL
				$('[data-category]').show();
				this.categoryTitles.show();
			}

			// Save state in URL
			saveState('cat', this.activeTab.text());
		},

		/**
		 * Show tabs and hide categories names
		 */
		showTabs: function() {
			if (!this.tabsEnabled)
				return;

			// If tabs are already shown, don't do anything
			if (this.content.attr('data-tabs') == 'true')
				return;

			this.content.attr('data-tabs', 'true');

			if (this.activeTab.text() == 'all') // Show all categories
				$('[data-category]').show();
			else // Only show activeTab category
				$('[data-category]').not('[data-category="' + this.activeTab.text() + '"]').hide();
		},

		/**
		 * Hide tabs and show categories names
		 */
		hideTabs: function() {
			if (!this.tabsEnabled)
				return;

			// If tabs are already hidden, don't do anything
			if (this.content.attr('data-tabs') == 'false')
				return;

			this.content.attr('data-tabs', 'false');

			// Show back every hidden category
			$('[data-category]').show();
		}
	};

	Tabs.defaults = Tabs.prototype.defaults;

	$.fn.tabs = function(options) {
		return new Tabs(this.first(), options).init();
	};

	window.Tabs = Tabs;
}(jQuery, window));
