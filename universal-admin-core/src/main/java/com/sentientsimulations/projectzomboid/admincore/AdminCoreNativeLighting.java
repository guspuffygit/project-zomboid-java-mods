package com.sentientsimulations.projectzomboid.admincore;

/** Read-only native visibility bits, without applying the observer's temporary sight answers. */
public interface AdminCoreNativeLighting {
    byte uacObserverVisibilityFlags();
}
