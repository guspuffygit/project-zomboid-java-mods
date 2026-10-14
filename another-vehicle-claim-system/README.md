# AVCS compatibility

| Optional integration | Protection |
| --- | --- |
| DAMN Library metadata | Preserves AVCS claim identity on the vehicle and legacy parts. Other DAMN commands stay unchanged. |

The guard installs when loaded and at server startup. After manually reloading DAMN handlers, reload the guard or restart the server.

The exact provider fixture accepts `-PdamnModDir=<DAMN version folder>` or `DAMN_MOD_ROOT`. No DAMN source is bundled.
