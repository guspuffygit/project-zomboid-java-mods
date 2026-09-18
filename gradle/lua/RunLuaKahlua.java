import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;

/** Runs fixtures in the installed game's interpreter without starting the game. */
class RunLuaKahlua {
    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            throw new IllegalArgumentException("Pass a Lua test script and its optional arguments");
        }
        var platform = J2SEPlatform.getInstance();
        KahluaTable environment = platform.newEnvironment();
        KahluaThread thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        LuaCompiler.rewriteEvents = false;
        environment.rawset(
                "print",
                (JavaFunction)
                        (frame, count) -> {
                            for (int i = 0; i < count; i++) {
                                if (i != 0) System.out.print("\t");
                                System.out.print(frame.get(i));
                            }
                            System.out.println();
                            return 0;
                        });
        KahluaTable arguments = platform.newTable();
        for (int i = 0; i < args.length; i++) arguments.rawset((double) i, args[i]);
        environment.rawset("arg", arguments);
        environment.rawset(
                "dofile",
                (JavaFunction)
                        (frame, count) -> {
                            String file = (String) frame.get(0);
                            try {
                                Object[] result = evaluate(thread, environment, file);
                                for (int i = 1; i < result.length; i++) frame.push(result[i]);
                                return result.length - 1;
                            } catch (Exception ex) {
                                throw new RuntimeException("Failed Lua file: " + file, ex);
                            }
                        });
        evaluate(thread, environment, args[0]);
    }

    private static Object[] evaluate(KahluaThread thread, KahluaTable environment, String file)
            throws Exception {
        Path source = Path.of(System.getProperty("lua.test.root", ".")).resolve(file);
        try (var reader = Files.newBufferedReader(source)) {
            Object[] result =
                    thread.pcall(LuaCompiler.loadis(reader, file, environment), new Object[0]);
            if (!Boolean.TRUE.equals(result[0])) {
                throw new IllegalStateException(file + ": " + Arrays.toString(result));
            }
            return result;
        }
    }
}
