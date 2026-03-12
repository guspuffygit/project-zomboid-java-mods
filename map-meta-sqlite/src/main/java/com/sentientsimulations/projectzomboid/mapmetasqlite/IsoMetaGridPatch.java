package com.sentientsimulations.projectzomboid.mapmetasqlite;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Patches {@code IsoMetaGrid.save()} and {@code IsoMetaGrid.load()} to persist SafeHouse data in a
 * SQLite database ({@code map_meta.db}) alongside the vanilla {@code map_meta.bin}.
 *
 * <p>On save, SafeHouse data is written to SQLite after the vanilla binary save completes. On load,
 * if {@code map_meta.db} exists, its SafeHouse data replaces the vanilla binary data in memory.
 *
 * <p>The vanilla {@code map_meta.bin} continues to be written normally for backwards compatibility.
 */
public class IsoMetaGridPatch extends StormClassTransformer {

    public IsoMetaGridPatch() {
        super("zombie.iso.IsoMetaGrid");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                        Advice.to(SaveAdvice.class)
                                .on(
                                        ElementMatchers.named("save")
                                                .and(ElementMatchers.takesNoArguments())
                                                .and(ElementMatchers.returns(void.class))))
                .visit(
                        Advice.to(LoadAdvice.class)
                                .on(
                                        ElementMatchers.named("load")
                                                .and(ElementMatchers.takesNoArguments())
                                                .and(ElementMatchers.returns(void.class))));
    }

    public static class SaveAdvice {

        @Advice.OnMethodExit
        public static void afterSave() {
            SafeHouseSqliteBridge.onSave();
        }
    }

    public static class LoadAdvice {

        @Advice.OnMethodExit
        public static void afterLoad() {
            SafeHouseSqliteBridge.onLoad();
        }
    }
}
