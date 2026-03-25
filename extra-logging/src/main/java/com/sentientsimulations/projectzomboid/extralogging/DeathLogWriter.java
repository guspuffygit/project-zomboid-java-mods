package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.encoder.PatternLayoutEncoder;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.FileAppender;
import org.slf4j.LoggerFactory;

public class DeathLogWriter {

    private static final String SEPARATOR =
            "================================================================================";

    private static final ch.qos.logback.classic.Logger deathLogger;

    static {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();

        String logHome = System.getProperty("STORM_LOG_DIR");
        if (logHome == null || logHome.isEmpty()) {
            logHome = System.getProperty("user.home") + "/Zomboid/Logs";
        }
        String logFile =
                System.getProperty("EXTRA_LOGGING_DIR", logHome + "/extra-logging/deaths.log");

        PatternLayoutEncoder encoder = new PatternLayoutEncoder();
        encoder.setContext(context);
        encoder.setPattern("%msg%n");
        encoder.start();

        FileAppender<ILoggingEvent> appender = new FileAppender<>();
        appender.setContext(context);
        appender.setName("EXTRA_LOGGING_DEATHS");
        appender.setFile(logFile);
        appender.setAppend(true);
        appender.setEncoder(encoder);
        appender.start();

        deathLogger = context.getLogger("extra-logging.deaths");
        deathLogger.setLevel(Level.INFO);
        deathLogger.setAdditive(false);
        deathLogger.addAppender(appender);

        LOGGER.info("Death log writer initialized, writing to: {}", logFile);
    }

    public static void writeDeathEntry(String header, String body) {
        deathLogger.info("{}\n{}\n{}\n{}", SEPARATOR, header, SEPARATOR, body);
    }
}
