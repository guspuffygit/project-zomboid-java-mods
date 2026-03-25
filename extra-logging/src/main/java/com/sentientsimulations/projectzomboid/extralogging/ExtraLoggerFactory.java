package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import ch.qos.logback.classic.AsyncAppender;
import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.encoder.PatternLayoutEncoder;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.rolling.FixedWindowRollingPolicy;
import ch.qos.logback.core.rolling.RollingFileAppender;
import ch.qos.logback.core.rolling.SizeBasedTriggeringPolicy;
import ch.qos.logback.core.util.FileSize;
import org.slf4j.LoggerFactory;

public class ExtraLoggerFactory {

    private static final String LOG_DIR;

    static {
        String logHome = System.getProperty("STORM_LOG_DIR");
        if (logHome == null || logHome.isEmpty()) {
            logHome = System.getProperty("user.home") + "/Zomboid/Logs";
        }
        LOG_DIR = System.getProperty("EXTRA_LOGGING_DIR", logHome + "/extra-logging");
    }

    public static ch.qos.logback.classic.Logger createLogger(String name) {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        String logFile = LOG_DIR + "/" + name + ".log";

        PatternLayoutEncoder encoder = new PatternLayoutEncoder();
        encoder.setContext(context);
        encoder.setPattern("%msg%n");
        encoder.start();

        RollingFileAppender<ILoggingEvent> rollingAppender = new RollingFileAppender<>();
        rollingAppender.setContext(context);
        rollingAppender.setName("EXTRA_LOGGING_" + name.toUpperCase() + "_FILE");
        rollingAppender.setFile(logFile);
        rollingAppender.setAppend(true);
        rollingAppender.setEncoder(encoder);

        FixedWindowRollingPolicy rollingPolicy = new FixedWindowRollingPolicy();
        rollingPolicy.setContext(context);
        rollingPolicy.setParent(rollingAppender);
        rollingPolicy.setFileNamePattern(LOG_DIR + "/" + name + ".%i.log");
        rollingPolicy.setMinIndex(1);
        rollingPolicy.setMaxIndex(1);
        rollingPolicy.start();

        SizeBasedTriggeringPolicy<ILoggingEvent> triggeringPolicy =
                new SizeBasedTriggeringPolicy<>();
        triggeringPolicy.setContext(context);
        triggeringPolicy.setMaxFileSize(FileSize.valueOf("20MB"));
        triggeringPolicy.start();

        rollingAppender.setRollingPolicy(rollingPolicy);
        rollingAppender.setTriggeringPolicy(triggeringPolicy);
        rollingAppender.start();

        AsyncAppender asyncAppender = new AsyncAppender();
        asyncAppender.setContext(context);
        asyncAppender.setName("ASYNC_EXTRA_LOGGING_" + name.toUpperCase());
        asyncAppender.addAppender(rollingAppender);
        asyncAppender.setQueueSize(512);
        asyncAppender.setDiscardingThreshold(0);
        asyncAppender.setIncludeCallerData(false);
        asyncAppender.start();

        ch.qos.logback.classic.Logger logger = context.getLogger("extra-logging." + name);
        logger.setLevel(Level.INFO);
        logger.setAdditive(false);
        logger.addAppender(asyncAppender);

        LOGGER.info("Extra logger [{}] initialized, writing to: {}", name, logFile);
        return logger;
    }
}
