package com.sentientsimulations.projectzomboid.extralogging;

public class SafehouseLogWriter {

    private static final String SEPARATOR =
            "================================================================================";

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("safehouses");

    public static void writeEntry(String header, String body) {
        logger.info("{}\n{}\n{}\n{}", SEPARATOR, header, SEPARATOR, body);
    }
}
