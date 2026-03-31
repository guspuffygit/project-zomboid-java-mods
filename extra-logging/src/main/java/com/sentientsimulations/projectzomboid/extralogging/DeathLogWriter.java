package com.sentientsimulations.projectzomboid.extralogging;

public class DeathLogWriter {

    private static final String SEPARATOR =
            "================================================================================";

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("deaths");

    public static void writeDeathEntry(String header, String body) {
        logger.info("{}\n{}\n{}\n{}", SEPARATOR, header, SEPARATOR, body);
    }
}
