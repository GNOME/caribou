namespace Caribou {
    /**
     * Singleton object providing access to the X Window facility.
     */
    public class XAdapter : DisplayAdapter {
        /* Private properties */
        unowned X.Display xdisplay;
        X.ID xid;
        Xkb.Desc xkbdesc;
        Xkl.Engine xkl_engine;
        uint reserved_keysym;
        uchar reserved_keycode;
        uchar modifiers;
        uchar group;
        uint[] level_switch_modifiers;

        private class KeyButtonHandler {
            public unowned KeyButtonCallback cb { get; private set; }
            public KeyButtonHandler (KeyButtonCallback cb) {
                this.cb = cb;
            }
        }

        Gee.HashMap<uint, KeyButtonHandler> button_funcs;
        Gee.HashMap<uint, KeyButtonHandler> key_funcs;

        construct {
            Xkb.State xkb_state;
            unowned Xkl.State xkl_state;

            Gdk.Window rootwin = Gdk.get_default_root_window();
            this.xdisplay = Gdk.X11Display.get_xdisplay (rootwin.get_display ());
            xid = Gdk.X11Window.get_xid (rootwin);
            this.xkbdesc = Xkb.get_keyboard (this.xdisplay,
                                             Xkb.GBN_AllComponentsMask,
                                             Xkb.UseCoreKbd);
            this.xkl_engine = Xkl.Engine.get_instance (this.xdisplay);
            xkl_engine.start_listen (Xkl.EngineListenModes.TRACK_KEYBOARD_STATE);
            xkl_state = this.xkl_engine.get_current_state ();
            this.group = (uchar) xkl_state.group;
            xkl_engine.X_state_changed.connect_after (xkl_state_changed);
            xkl_engine.X_config_changed.connect_after (xkl_config_changed);

            Xkb.get_state (this.xdisplay, Xkb.UseCoreKbd, out xkb_state);
            this.modifiers = xkb_state.mods;

            this.reserved_keycode = 0;

            this.level_switch_modifiers = {
                0,
                Gdk.ModifierType.SHIFT_MASK
            };
            var lv3_mod = keysym_to_modifier (Gdk.Key.ISO_Level3_Shift);
            if (lv3_mod != 0) {
                level_switch_modifiers += lv3_mod;
                level_switch_modifiers += Gdk.ModifierType.SHIFT_MASK | lv3_mod;
            }

            button_funcs = new Gee.HashMap<uint, KeyButtonHandler> ();

            key_funcs = new Gee.HashMap<uint, KeyButtonHandler> ();

            Xkb.select_events (
                this.xdisplay, Xkb.UseCoreKbd,
                Xkb.StateNotifyMask | Xkb.AccessXNotifyMask,
                Xkb.StateNotifyMask | Xkb.AccessXNotifyMask);

            ((Gdk.Window) null).add_filter (x_event_filter); // Did I blow your mind?
        }

        ~XAdapter () {
            Xkb.free_keyboard(this.xkbdesc, Xkb.GBN_AllComponentsMask, true);
        }

        private bool set_slowkeys_enabled (bool enable) {
            Xkb.get_controls (this.xdisplay, Xkb.AllControlsMask, this.xkbdesc);

            var previous =
                (this.xkbdesc.ctrls.enabled_ctrls & Xkb.SlowKeysMask) != 0;

            if (enable)
                this.xkbdesc.ctrls.enabled_ctrls |= Xkb.SlowKeysMask;
            else
                this.xkbdesc.ctrls.enabled_ctrls &= ~Xkb.SlowKeysMask;

            Xkb.set_controls (this.xdisplay,
                              Xkb.SlowKeysMask | Xkb.ControlsEnabledMask,
                              this.xkbdesc);

            return previous;
        }

        private Gdk.FilterReturn x_event_filter (Gdk.XEvent xevent, Gdk.Event event) {
            // After the following commit, Vala changed the definition
            // of Gdk.XEvent from struct to class:
            // http://git.gnome.org/browse/vala/commit/?id=9c52e7b7
            //
            // This affects the meaning of address-of (&) operator:
            // '&xevent' now refers to the address of XEvent*, not
            // XEvent.
#if VALA_0_16
            void* pointer = xevent;
#else
            void* pointer = &xevent;
#endif
            Xkb.Event* xkbev = (Xkb.Event *) pointer;
            X.Event* xev = (X.Event *) pointer;

            this.xkl_engine.filter_events(xev);

            if (xev.type == X.EventType.ButtonPress ||
                xev.type == X.EventType.ButtonRelease) {
                KeyButtonHandler handler =
                    (KeyButtonHandler) button_funcs.get (xev.xbutton.button);
                if (handler != null)
                    handler.cb (xev.xbutton.button,
                                xev.type == X.EventType.ButtonPress);
            } else if (xev.type == X.EventType.KeyPress ||
                       xev.type == X.EventType.KeyRelease) {

                KeyButtonHandler handler =
                    (KeyButtonHandler) key_funcs.get (xev.xkey.keycode);
                if (handler != null)
                    handler.cb (xev.xkey.keycode,
                                xev.type == X.EventType.KeyPress);
            } else if (xkbev.any.xkb_type == Xkb.StateNotify) {
                Xkb.StateNotifyEvent *sevent = &xkbev.state;
                if ((sevent.changed & Xkb.ModifierStateMask) != 0) {
                    this.modifiers = (uchar) sevent.mods;
                }
            }

            return Gdk.FilterReturn.CONTINUE;
        }

        private void xkl_state_changed (int type, int group, bool restore) {
            string group_name;
            string variant_name;

            this.group = (uchar) group;
            get_current_group (out group_name, out variant_name);
            group_changed (this.group, group_name, variant_name);
        }

        private void xkl_config_changed () {
            config_changed ();
        }

        private uchar keysym_to_modifier (uint keyval) {
            for (int i = xkbdesc.min_key_code; i <= xkbdesc.max_key_code; i++) {
                unowned Xkb.SymMap symmap = xkbdesc.map.key_sym_map[i];
                for (int j = 0;
                     j < symmap.width * (symmap.group_info & 0x0f);
                     j++)
                    if (xkbdesc.map.syms[symmap.offset + j] == keyval)
                        return xkbdesc.map.modmap[i];
            }
            return 0;
        }

        private uchar get_reserved_keycode () {
            int i;
            unowned Xkb.Desc xkbdesc = this.xkbdesc;

            for (i = xkbdesc.max_key_code; i >= xkbdesc.min_key_code; --i) {
                if (xkbdesc.map.key_sym_map[i].kt_index[0] == Xkb.OneLevelIndex) {
                    if (this.xdisplay.keycode_to_keysym ((uchar) i, 0) != 0) {
                        Gdk.error_trap_push ();
                        this.xdisplay.grab_key (i, 0,
                                    Gdk.x11_get_default_root_xwindow (), true,
                                    X.GrabMode.Sync, X.GrabMode.Sync);
                        this.xdisplay.flush ();
                        this.xdisplay.ungrab_key (
                            i, 0, Gdk.x11_get_default_root_xwindow ());
                        if (Gdk.error_trap_pop () == 0)
                            return (uchar) i;
                    }
                }
            }

            return (uchar) this.xdisplay.keysym_to_keycode (0x0023); // XK_numbersign
        }

        private void replace_keycode (uint keysym) {
            if (this.reserved_keycode == 0) {
                this.reserved_keycode = get_reserved_keycode ();
                this.reserved_keysym = (uint) this.xdisplay.keycode_to_keysym (
                    this.reserved_keycode, 0);
            }

            this.xdisplay.flush ();
            uint offset = this.xkbdesc.map.key_sym_map[this.reserved_keycode].offset;
            this.xkbdesc.map.syms[offset] = keysym;
            this.xkbdesc.device_spec = (ushort) Xkb.UseCoreKbd;

            Xkb.MapChanges changes = Xkb.MapChanges ();

            changes.changed = (ushort) Xkb.KeySymsMask;
            changes.first_key_sym = (char) this.reserved_keycode;
            changes.num_key_syms = this.xkbdesc.map.key_sym_map[this.reserved_keycode].width;

            Xkb.change_map (this.xdisplay, this.xkbdesc, changes);

            this.xdisplay.flush ();

            if (keysym != this.reserved_keysym)
                GLib.Timeout.add (500, reset_reserved);
        }

        private bool reset_reserved () {
            replace_keycode (this.reserved_keysym);
            return false;
        }

        private bool best_keycode_keyval_match (uint keyval,
                                                out uchar keycode,
                                                out uint modmask) {
            Gdk.Keymap kmap= Gdk.Keymap.get_default ();
            Gdk.KeymapKey[] kmk;

            keycode = 0;
            modmask = 0;

            if (!kmap.get_entries_for_keyval (keyval, out kmk))
                return false;

            Gdk.KeymapKey? best_match = null;

            foreach (Gdk.KeymapKey km in kmk)
               if (km.group == this.group &&
                   km.level < this.level_switch_modifiers.length)
                   best_match = km;

            if (best_match == null)
                return false;

            keycode = (uchar) best_match.keycode;
            modmask = this.level_switch_modifiers[best_match.level];

            return true;
        }

        private uchar keycode_for_keyval (uint keyval, out uint modmask) {
            uchar keycode = 0;

            if (!best_keycode_keyval_match (keyval, out keycode, out modmask)) {
                replace_keycode (keyval);
                keycode = this.reserved_keycode;
                modmask = 0;
            }

            return keycode;
        }

        public override void keyval_press (uint keyval) {
            uint mask;
            uchar keycode = keycode_for_keyval (keyval, out mask);

            if (mask != 0)
                mod_latch (mask);

            var enabled = set_slowkeys_enabled (false);
            XTest.fake_key_event (this.xdisplay, keycode, true, X.CURRENT_TIME);
            this.xdisplay.flush ();
            set_slowkeys_enabled (enabled);
        }

        public override void keyval_release (uint keyval) {
            uchar keycode = keycode_for_keyval (keyval, null);

            XTest.fake_key_event (this.xdisplay, keycode, false, X.CURRENT_TIME);
            this.xdisplay.flush ();
        }

        public override void mod_lock (uint mask) {
            Xkb.lock_modifiers (this.xdisplay, Xkb.UseCoreKbd, mask, mask);
            this.xdisplay.flush ();
        }

        public override void mod_unlock (uint mask) {
            Xkb.lock_modifiers (this.xdisplay, Xkb.UseCoreKbd, mask, 0);
            this.xdisplay.flush();
        }

        public override void mod_latch (uint mask) {
            Xkb.latch_modifiers (this.xdisplay, Xkb.UseCoreKbd, mask, mask);
            this.xdisplay.flush ();
        }

        public override void mod_unlatch (uint mask) {
            Xkb.latch_modifiers (this.xdisplay, Xkb.UseCoreKbd, mask, 0);
            this.xdisplay.flush ();
        }

        public override uint get_current_group (out string group_name,
                                       out string variant_name) {
            Xkl.ConfigRec config_rec = new Xkl.ConfigRec ();
            config_rec.get_from_server (this.xkl_engine);

            if (this.group < config_rec.layouts.length)
                group_name = config_rec.layouts[this.group];
            else
                group_name = "";

            if (this.group < config_rec.variants.length)
                variant_name = config_rec.variants[this.group];
            else
                variant_name = "";

            if (variant_name == null)
                variant_name = "";

            return this.group;
        }

        public override void get_groups (out string[] group_names,
                                out string[] variant_names) {
            int i;
            Xkl.ConfigRec config_rec = new Xkl.ConfigRec ();
            config_rec.get_from_server (this.xkl_engine);

            for (i=0; i<4; i++)
                if (config_rec.layouts[i] == null) {
                    i--;
                    break;
                }

            group_names = new string[i+1];
            variant_names = new string[i+1];

            for (; i>=0; i--) {
                group_names[i] = config_rec.layouts[i];
                if (config_rec.variants[i] != null)
                    variant_names[i] = config_rec.variants[i];
                else
                    variant_names[i] = "";
            }
        }

        public override void register_key_func (uint keyval,
                                                KeyButtonCallback? func)
        {
            uchar keycode;
            uint modmask;

            if (!best_keycode_keyval_match (keyval, out keycode, out modmask)) {
                GLib.warning ("No good keycode for %d", (int) keyval);
                return;
            }

            if (func != null) {
                var handler = new KeyButtonHandler (func);
                key_funcs.set (keycode, handler);
                xdisplay.grab_key ((int)keycode, 0, xid,
                                   true, X.GrabMode.Async, X.GrabMode.Async);

            } else {
                key_funcs.unset (keycode);
                xdisplay.ungrab_key ((int)keycode, 0, xid);
            }
        }

        public override void register_button_func (uint button,
                                                   KeyButtonCallback? func)
        {
            if (func != null) {
                var handler = new KeyButtonHandler (func);
                button_funcs.set (button, handler);
                xdisplay.grab_button (button, 0, xid, true,
                                      X.EventMask.ButtonPressMask |
                                      X.EventMask.ButtonReleaseMask,
                                      X.GrabMode.Async, X.GrabMode.Async, 0, 0);

            } else {
                button_funcs.unset (button);
                xdisplay.ungrab_button (button, 0, xid);
            }
        }
    }
}
