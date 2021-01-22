namespace Caribou {
    /**
     * Object representing a key in a column.
     *
     * This is used for implementing custom keyboard service.
     */
    public class KeyModel : GLib.Object, IScannableItem, IKeyboardObject {
        public string align { get; set; default = "center"; }
        public double width { get; set; default = 1.0; }
        public string toggle { get; set; default = ""; }
        public bool repeatable { get; set; default = false; }

        private Gdk.ModifierType mod_mask;
        public bool is_modifier {
            get {
                return (mod_mask != 0);
            }

            set {}
        }

        public ModifierState modifier_state;

        public bool show_subkeys { get; private set; default = false; }
        public string name { get; private set; }
        public uint keyval { get; private set; }
        public string? text { get; private construct set; default = null; }
        private uint[] _keyvals = {};
        public string label { get; set; default = ""; }

        public bool scan_stepping { get; internal set; }
        private bool _scan_selected;
        public bool scan_selected {
            get {
                return _scan_selected;
            }

            internal set {
                _scan_selected = value;
                if (_scan_selected)
                    activate ();
            }
        }

        private uint hold_tid;
        private DisplayAdapter xadapter;
        private Gee.ArrayList<KeyModel> extended_keys;

        public signal void key_hold_end ();
        public signal void key_hold ();

        private const ModifierMapEntry mod_map[] = {
            { "Control_L", Gdk.ModifierType.CONTROL_MASK },
            { "Alt_L", Gdk.ModifierType.MOD1_MASK },
            { null, 0 }
        };

        private const LabelMapEntry label_map[] = {
            { "BackSpace", "\xe2\x8c\xab" },
            { "space", " " },
            { "Delete", "\xe2\x8c\xa6" },
            { "Return", "\xe2\x8f\x8e" },
            { "Escape", "Esc" },
            { "Tab", "\xe2\x86\xb9"},
            { "Control_L", "Ctrl" },
            { "Control_R", "Ctrl" },
            { "Alt_L", "Alt" },
            { "Alt_R", "Alt" },
            { "Up", "\xe2\x87\xa1"},
            { "Down", "\xe2\x87\xa3"},
            { "Left", "\xe2\x87\xa0"},
            { "Right", "\xe2\x87\xa2"},
            { "Prior", "Page\nUp" },
            { "Next", "Page\nDown" },
            { "Caribou_Prefs", "\xe2\x8c\xa8" },
            { "Caribou_ShiftUp", "\xe2\xac\x86" },
            { "Caribou_ShiftDown", "\xe2\xac\x87" },
            { "Caribou_Emoticons", "\xe2\x98\xba" },
            { "Caribou_Symbols", "123" },
            { "Caribou_Symbols_More", "{#*" },
            { "Caribou_Alpha", "Abc" },
            { "Caribou_Repeat", "\xe2\x99\xbb" }
        };

        public KeyModel (string name, string? text = null) {
            this.name = name;
            this.text = text;
            mod_mask = (Gdk.ModifierType) 0;

            int i = 0;
            for (ModifierMapEntry entry=mod_map[i];
                 entry.name != null;
                 entry=mod_map[++i]) {
                if (name == entry.name)
                    mod_mask = entry.mask;
            }

            if (mod_mask == 0) {
                if (text != null) {
                    int index = 0;
                    unichar uc;
                    while (text.get_next_char (ref index, out uc)) {
                        uint keyval = Gdk.unicode_to_keyval (uc);
                        if (keyval != (uc | 0x01000000))
                            _keyvals += keyval;
                    }
                } else {
                    uint keyval = Gdk.keyval_from_name (name);
                    if (keyval != Gdk.Key.VoidSymbol && keyval != 0)
                        _keyvals += keyval;
                    this.keyval = keyval;
                }
            }

            for (i = 0; i < label_map.length; i++) {
                if (label_map[i].name == name) {
                    label = label_map[i].label;
                    break;
                }
            }

            if (i == label_map.length) {
                if (text != null)
                    label = text;
                else if (name.has_prefix ("Caribou_"))
                    label = name["Caribou_".length:name.length];
                else {
                    // Try to use Unicode symbol as label.
                    if (_keyvals.length > 0) {
                        unichar uc = Gdk.keyval_to_unicode (_keyvals[0]);
                        if (!uc.isspace () && uc != 0)
                            label = uc.to_string ();
                    }
                    // If no usable Unicode symbol is assigned to the
                    // key, guess the best possible label.
                    //
                    // First, it is known that dead keys are not
                    // assigned Unicode symbols.  Use the ones
                    // assigned to non-dead keys instead.
                    if (label == "" && name.has_prefix ("dead_")) {
                        uint keyval = Gdk.keyval_from_name (name["dead_".length:name.length]);
                        unichar uc = Gdk.keyval_to_unicode (keyval);
                        if (!uc.isspace () && uc != 0)
                            label = uc.to_string ();
                    }
                    // Second, use the key name as label.
                    if (label == "" && _keyvals.length > 0)
                        label = name;
                }
            }

            xadapter = DisplayAdapter.get_default();
            extended_keys = new Gee.ArrayList<KeyModel> ();
        }

        internal void add_subkey (KeyModel key) {
            key.key_released.connect(on_subkey_released);
            extended_keys.add (key);
        }

        private void on_subkey_released (KeyModel key) {
            key_released (key);
            show_subkeys = false;
        }

        public void press () {
            if (is_modifier) {
                if (modifier_state == ModifierState.NONE) {
                    modifier_state = ModifierState.LATCHED;
                    xadapter.mod_lock(mod_mask);
                } else {
                    modifier_state = ModifierState.NONE;
                }
            }

            if (repeatable)
                xadapter.keyval_press (keyval);
            else
                hold_tid = GLib.Timeout.add (1000, on_key_held);

            key_pressed(this);
        }

        public void release () {
            if (hold_tid != 0)
                GLib.Source.remove (hold_tid);

            if (is_modifier) {
                if (modifier_state == ModifierState.NONE) {
                    xadapter.mod_unlock(mod_mask);
                } else {
                    return;
                }
            }

            if (repeatable)
                xadapter.keyval_release (keyval);
            else {
                foreach (var keyval in _keyvals) {
                    xadapter.keyval_press (keyval);
                    xadapter.keyval_release (keyval);
                }
            }

            key_released(this);

            if (hold_tid != 0) {
                key_clicked (this);
                hold_tid = 0;
            } else {
                key_hold_end ();
            }
        }

        private bool on_key_held () {
            hold_tid = 0;
            if (extended_keys.size != 0)
                show_subkeys = true;
            if (is_modifier && modifier_state == ModifierState.LATCHED)
                modifier_state = ModifierState.LOCKED;
            key_hold ();
            return false;
        }

        public KeyModel[] get_extended_keys () {
            return (KeyModel[]) extended_keys.to_array ();
        }

        public KeyModel[] get_keys () {
            Gee.ArrayList<KeyModel> all_keys = new Gee.ArrayList<KeyModel> ();
            all_keys.add (this);
            all_keys.add_all (extended_keys);
            return (KeyModel[]) all_keys.to_array ();
        }

        public IKeyboardObject[] get_children () {
            return (IKeyboardObject[]) extended_keys.to_array ();
        }

        public void activate () {
            press ();
            GLib.Timeout.add(200, () => { release (); return false; });
        }
    }

    public enum ModifierState {
        NONE,
        LATCHED,
        LOCKED
    }

    private struct ModifierMapEntry {
        string name;
        Gdk.ModifierType mask;
    }

    private struct LabelMapEntry {
        string name;
        string label;
    }
}
