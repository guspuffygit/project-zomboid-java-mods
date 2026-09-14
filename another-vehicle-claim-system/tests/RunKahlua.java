import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;

/** Runs UI regression harnesses in the installed game's Lua interpreter. */
class RunKahlua {
    public static void main(String[] args) throws Exception {
        var platform = J2SEPlatform.getInstance();
        KahluaTable env = platform.newEnvironment();
        KahluaThread thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaCompiler.rewriteEvents = false;
        env.rawset("print", (JavaFunction)(frame, count) -> {
            for (int i = 0; i < count; i++) System.out.println(frame.get(i));
            return 0;
        });
        KahluaTable argv = platform.newTable();
        for (int i = 1; i < args.length; i++) argv.rawset((double)i, args[i]);
        env.rawset("arg", argv);
        env.rawset("dofile", (JavaFunction)(frame, count) -> {
            String file = (String)frame.get(0);
            try (var reader = Files.newBufferedReader(Path.of(file))) {
                Object[] result = thread.pcall(LuaCompiler.loadis(reader, file, env), new Object[0]);
                if (!Boolean.TRUE.equals(result[0])) throw new IllegalStateException(java.util.Arrays.toString(result));
                return 0;
            } catch (Exception ex) { throw new RuntimeException("Failed Lua file: " + file, ex); }
        });
        try (var reader = Files.newBufferedReader(Path.of(args[0]))) {
            Object[] result = thread.pcall(LuaCompiler.loadis(reader, args[0], env), new Object[0]);
            if (!Boolean.TRUE.equals(result[0])) throw new IllegalStateException(java.util.Arrays.toString(result));
        }
    }
}
