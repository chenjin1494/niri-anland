fn main() {
    println!("cargo:rustc-check-cfg=cfg(have_libinput_plugin_system)");
    if pkg_config::Config::new()
        .atleast_version("1.30.0")
        .probe("libinput")
        .is_ok()
    {
        println!("cargo:rustc-cfg=have_libinput_plugin_system");
    }

    println!("cargo:rustc-check-cfg=cfg(have_anland_audio)");
    if std::env::var_os("CARGO_FEATURE_ANLAND").is_some() {
        if pkg_config::Config::new().probe("libpipewire-0.3").is_ok() {
            println!("cargo:rustc-cfg=have_anland_audio");
        }
        let lib = std::env::var("ANLAND_NIRI_BRIDGE_BUILD")
            .expect("the `anland` feature requires ANLAND_NIRI_BRIDGE_BUILD");
        println!("cargo:rustc-link-search=native={lib}");
        println!("cargo:rustc-link-search=native={lib}/common/libdisplay_producer");
        println!("cargo:rustc-link-lib=dylib=anland_niri_bridge");
        println!("cargo:rustc-link-lib=dylib=display_producer");
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN/../lib");
        println!("cargo:rerun-if-env-changed=ANLAND_NIRI_BRIDGE_BUILD");
    }
}
