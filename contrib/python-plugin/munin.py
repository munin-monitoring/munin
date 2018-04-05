#!/usr/bin/env python

"""
Makes it easy to create munin plugins...

    http://munin-monitoring.org/wiki/protocol-config

Morten Siebuhr
sbhr@sbhr.dk
12/12 2008
"""


def getOptionOrDefault(option, default=None):  # noqa: N802
    from os import environ
    return environ.setdefault(option, default)


class DataSource(object):
    """Represents a single data source.

    This class should not be directly created by the user - this is done
    transparently by the Plugin-class."""

    __slots__ = ['label', 'cdef', 'draw', 'graph', 'info', 'extinfo', 'max',
                 'min', 'negative', 'type', 'warning', 'critical', 'colour',
                 'skipdraw', 'sum', 'stack', 'line', 'value']

    # Allowed draw modes
    _draw_modes = ['AREA', 'STACK',
                   'LINE1', 'LINE2', 'LINE3',
                   'LINESTACK1', 'LINESTACK2', 'LINESTACK3',
                   'AREASTACK']

    def get_config(self):
        if hasattr(self, "draw"):
            assert self.draw in self._draw_modes

        data = dict()

        for attr in self.__slots__:
            if attr == 'value':
                continue
            if hasattr(self, attr):
                data[attr] = self.__getattribute__(attr)

        return data

    def get_value(self, data_source_name):
        assert hasattr(self, "value")

        if callable(self.value):
            return self.value(data_source_name)

        return self.value


class Plugin(object):
    """Facilitates OO creation of Munin plugins.

    #!/usr/bin/env python
    from munin import Plugin

    p = Plugin("Test measurement", "test/second", category="junk")
    p.autoconf = False

    for name, value in {'a': 1, 'b': 2}:
        p[ name ].label = name
        p[ name ].value = value

    p.run()

    (It will itself detect how the script is called and create the proper
    output.)

     * If 'autoconf' is a callable, it will be called when running autoconf.

    """

    def __init__(self, title, vlabel,
                 category="misc", info="", args="", scale=True):
        """Sets up the plugin; title, vertical label, category -- all things
        that are global for the plugin.
        """

        self.title = title
        self.vlabel = vlabel
        self.category = category
        self.info = info
        self.args = args
        self.scale = scale

        self._values = dict()

        assert type(title) is str
        assert type(vlabel) is str
        assert type(category) is str

    def __getitem__(self, key):
        if key not in self._values:
            self._values[key] = DataSource()
        return self._values[key]

    def __setitem__(self, key, value):
        self._values[key] = value

    def __delitem__(self, key):
        if key in self._values:
            del self._values[key]

    def __contains__(self, key):
        return key in self._values

    def _print_values(self):
        """Print the values for all registered data sources.

        Similar to running with "values"-argument."""
        for prefix, line in self._values.items():
            value = line.get_value(prefix)
            assert type(value) is int
            print("%s.value %s" % (prefix, value))

    def _print_config(self):
        """Print the output needed for setting up the graph - i.e. when the
        plugin is run with "config"-argument."""
        # Print graph_-variables

        for prop in ['title', 'category', 'vlabel', 'info', 'args', 'draw']:
            if prop not in self.__dict__:
                continue
            if not self.__dict__[prop]:
                continue
            print("graph_%s %s" % (prop, self.__dict__[prop]))

        # Print setup for individual lines
        for prefix, line in self._values.items():

            # The "label" attribute MUST be defined
            assert "label" in line.get_config().keys(), "No 'label' defined."

            for attr, value in line.get_config().items():
                print("%s.%s %s" % (prefix, attr, value))

    def _print_autoconf(self):
        """Running autoconf-mode."""
        aconf = False

        if hasattr(self, "autoconf"):
            if callable(self.autoconf):
                aconf = self.autoconf()
            else:
                aconf = self.autoconf

        if bool(aconf):
            print("YES")
        else:
            print("NO")

    def run(self, force_mode=None):
        """Run the plugin and "do the right thing"^(TM)."""

        mode = force_mode

        if mode is None:
            import sys
            if len(sys.argv) == 2:
                mode = sys.argv[1]

        if mode == "autoconf":
            self._print_autoconf()
            return

        if mode == "config":
            self._print_config()
            return

        self._print_values()
