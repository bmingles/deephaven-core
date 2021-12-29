package io.deephaven.server.jetty;

import io.deephaven.base.system.PrintStreamGlobals;
import io.deephaven.configuration.Configuration;
import io.deephaven.server.runner.Main;

import java.io.IOException;
import java.util.concurrent.TimeoutException;

public class JettyMain extends Main {
    public static void main(String[] args)
            throws IOException, InterruptedException, ClassNotFoundException, TimeoutException {
        final Configuration config = init(args, Main.class);

        // defaults to 5 minutes
        int httpSessionExpireMs = config.getIntegerWithDefault("http.session.durationMs", 300000);
        int httpPort = config.getIntegerWithDefault("http.port", 10000);
        int schedulerPoolSize = config.getIntegerWithDefault("scheduler.poolSize", 4);

        DaggerJettyServerComponent
                .builder()
                .withPort(httpPort)
                .withSchedulerPoolSize(schedulerPoolSize)
                .withSessionTokenExpireTmMs(httpSessionExpireMs)
                .withOut(PrintStreamGlobals.getOut())
                .withErr(PrintStreamGlobals.getErr())
                .build()
                .getServer()
                .run();
    }
}