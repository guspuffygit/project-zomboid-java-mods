package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.logging.StormFileLoggerFactory;
import org.slf4j.Logger;

/**
 * Thin wrapper around {@link StormFileLoggerFactory} that gives extra-logging its own log directory
 * (defaulting to {@code <STORM_LOG_DIR>/extra-logging/}, overridable via {@code
 * -DEXTRA_LOGGING_DIR=…}) and the mod's preferred size/rotation settings (20&nbsp;MB active file
 * with one rolled archive). JSON files use the bare {@code %msg%n} layout so each line is a
 * standalone JSON record; other extensions get the standard timestamped layout.
 */
public final class ExtraLoggerFactory {

    private static final String LOG_DIR =
            System.getProperty(
                    "EXTRA_LOGGING_DIR", StormFileLoggerFactory.LOG_HOME + "/extra-logging");

    private ExtraLoggerFactory() {}

    public static Logger createLogger(String name, String extension) {
        String pattern = "json".equals(extension) ? "%msg%n" : null;
        return StormFileLoggerFactory.create(
                "extra-logging." + name + "." + extension,
                LOG_DIR,
                name,
                extension,
                20,
                1,
                pattern);
    }

    public static Logger createLogger(String name) {
        return createLogger(name, "log");
    }
}
