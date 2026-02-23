package com.sentientsimulations.projectzomboid.shoutcast;

import static fmod.fmod.FMODManager.*;
import static fmod.fmod.FMODManager.FMOD_INIT_VOL0_BECOMES_VIRTUAL;
import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import fmod.javafmod;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnGameStartEvent;
import io.pzstorm.storm.event.lua.OnSendMessageToChatEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.jna.fmod.FmodJNA;
import io.pzstorm.storm.jna.fmod.models.FmodVector;
import io.pzstorm.storm.jna.fmod.results.ChannelGet3DAttributesResult;
import io.pzstorm.storm.jna.fmod.results.ChannelGet3DConeOrientationResult;
import io.pzstorm.storm.jna.fmod.results.ChannelGet3DConeSettingsResult;
import io.pzstorm.storm.lua.LuaManagerUtils;
import io.pzstorm.storm.mod.ZomboidMod;
import zombie.characters.IsoPlayer;

public class ShoutcastStreamer implements ZomboidMod {
    private static final FmodVector RADIO_POS = new FmodVector(5867.0f, 5216.0f, 0.0f);

    public static final long FMOD_CREATESTREAM = 0x00000080L;

    public static final long FMOD_3D = 0x00000010L;

    private static final float MIN_CLEAR_DIST = 21.0f;

    private static final float MAX_MUFFLE_DIST = 25.0f;

    private static final float LOWEST_GAIN_FLOOR = 0.1f;

    private Thread radioThread;
    private static long currentChannelHandle = 0;
    private static Long systemHandle = null;
    private static Boolean atfModLoaded = false;

    public static long playInternetRadio(String url) {
        if (systemHandle == null) {
            systemHandle = FmodJNA.FMOD_System_Create();
            FmodJNA.FMOD_System_Init(
                    systemHandle,
                    1024,
                    FMOD_INIT_NORMAL
                            | FMOD_INIT_CHANNEL_DISTANCEFILTER
                            | FMOD_INIT_CHANNEL_LOWPASS
                            | FMOD_INIT_VOL0_BECOMES_VIRTUAL);
            FmodJNA.FMOD_System_Set3DSettings(systemHandle, 1.0F, 1.0F, 1.0F);
        }

        long flags = FMOD_CREATESTREAM | FMOD_3D;

        LOGGER.debug("ZomboidRadio: Connecting to {}", url);

        long soundHandle = FmodJNA.FMOD_System_CreateSound(systemHandle, url, flags);

        LOGGER.debug("INTERNET_RADIO_SOUND_HANDLE: {}", soundHandle);

        if (soundHandle == 0) {
            LOGGER.error("ZomboidRadio: Failed to create sound handle (Bad URL or Network).");
            return 0;
        }

        LOGGER.debug("ZomboidRadio: Sound created, attempting to play...");

        long channelHandle = FmodJNA.FMOD_System_PlaySound(systemHandle, soundHandle, false);

        LOGGER.debug("INTERNET_RADIO_CHANNEL_HANDLE: {}", channelHandle);

        ChannelGet3DAttributesResult get3DAttributesResult =
                FmodJNA.FMOD_Channel_Get3DAttributes(channelHandle);
        LOGGER.debug(
                "FMOD_Channel_Get3DAttributes: Position {} Velocity {}",
                get3DAttributesResult.getPosition(),
                get3DAttributesResult.getVelocity());

        FmodJNA.FMOD_Channel_Set3DConeOrientation(channelHandle, new FmodVector(0f, 1f, 0f));
        FmodJNA.FMOD_Channel_Set3DConeSettings(channelHandle, 60.0f, 120.0f, 0.4f);

        FmodJNA.FMOD_Channel_Set3DMinMaxDistance(channelHandle, 23.0f, 75.0f);
        FmodJNA.FMOD_Channel_Set3DAttributes(
                channelHandle, new FmodVector(5867.0f, 5216.0f, 0.0f), new FmodVector(0f, 0f, 0f));

        ChannelGet3DConeSettingsResult coneSettings =
                FmodJNA.FMOD_Channel_Get3DConeSettings(channelHandle);
        LOGGER.debug(
                "coneSettings: inside: {}, outside: {}, outsideVolume: {}",
                coneSettings.getInsideConeAngle(),
                coneSettings.getOutsideConeAngle(),
                coneSettings.getOutsideVolume());

        ChannelGet3DConeOrientationResult coneOrientation =
                FmodJNA.FMOD_Channel_Get3DConeOrientation(channelHandle);
        LOGGER.debug("coneOrientation {}", coneOrientation.getVector());

        LOGGER.debug("ZomboidRadio: Success! Channel: {}", channelHandle);
        return channelHandle;
    }

    public static void onTick() {
        IsoPlayer player = IsoPlayer.getInstance();
        if (player == null
                || systemHandle == null
                || systemHandle == 0) { // Ensure systemHandle is valid
            return;
        }

        FmodVector vel = new FmodVector(0.0f, 0.0f, 0.0f);
        FmodVector pos = new FmodVector(player.getX(), player.getY(), player.getZ());
        FmodVector forward = new FmodVector(0.0f, -1.0f, 0.0f);
        FmodVector up = new FmodVector(0.0f, 0.0f, 1.0f);

        FmodJNA.FMOD_System_Set3DListenerAttributes(systemHandle, 0, pos, vel, forward, up);

        applyOcclusionFilter(player);

        FmodJNA.FMOD_System_Update(systemHandle);
    }

    private static void applyOcclusionFilter(IsoPlayer player) {
        float dx = player.getX() - RADIO_POS.getX();
        float dy = player.getY() - RADIO_POS.getY();
        double distance = Math.sqrt((dx * dx) + (dy * dy));

        float finalGain;

        if (distance <= MIN_CLEAR_DIST) {
            // We are very close: Full Clarity
            finalGain = 1.0f;
        } else if (distance >= MAX_MUFFLE_DIST) {
            // We are very far: Maximum Muffle
            finalGain = LOWEST_GAIN_FLOOR;
        } else {
            float transitionRange = MAX_MUFFLE_DIST - MIN_CLEAR_DIST;

            float distanceIntoZone = (float) distance - MIN_CLEAR_DIST;

            float fraction = distanceIntoZone / transitionRange;

            finalGain = 1.0f + (LOWEST_GAIN_FLOOR - 1.0f) * fraction;
        }

        if (currentChannelHandle != 0) {
            javafmod.FMOD_Channel_SetLowPassGain(currentChannelHandle, finalGain);
        }
    }

    public static void stopStream(long channelHandle) {
        if (channelHandle != 0) {
            javafmod.FMOD_Channel_Stop(channelHandle);
        }
    }

    @SubscribeEvent
    public void handleGameStart(OnGameStartEvent event) {
        if (atfModLoaded) {
            startRadioSequence();
        }
    }

    @SubscribeEvent
    public void onResetLuaEvent(OnZomboidGlobalsLoadEvent event) {
        Object atfFunction = LuaManagerUtils.getEnv().rawget("ATF_SetGlobalLighting");

        atfModLoaded = (atfFunction != null);
    }

    @SubscribeEvent
    public void handleOnTick(OnTickEvent event) {
        onTick();
    }

    private void startRadioSequence() {
        try {
            if (radioThread != null && radioThread.isAlive()) {
                LOGGER.debug("Interrupting existing radio thread...");
                radioThread.interrupt();
            }

            if (currentChannelHandle != 0) {
                LOGGER.debug("Stopping existing radio channel: {}", currentChannelHandle);
                stopStream(currentChannelHandle);
                currentChannelHandle = 0;
            }

            radioThread =
                    new Thread(
                            () -> {
                                try {
                                    Thread.sleep(10000);

                                    LOGGER.debug("STARTINGPLAYINGINOQWIJDOQIWJD version 1");

                                    currentChannelHandle =
                                            ShoutcastStreamer.playInternetRadio(
                                                    "http://icecast.guspuffy.com:8253/testing");
                                } catch (InterruptedException e) {
                                    LOGGER.info(
                                            "Radio thread was interrupted (Restarted or Stopped).");
                                } catch (Exception e) {
                                    LOGGER.error("Error inside radio thread", e);
                                }
                            });

            radioThread.start();
            LOGGER.debug("New radio thread started.");

        } catch (Exception e) {
            LOGGER.error("Failed to start radio sequence", e);
        }
    }

    // TODO: Add command handler to the mod framework
    @SubscribeEvent
    public void handleSendMessageToChat(OnSendMessageToChatEvent event) {
        try {
            if (event.message.trim().startsWith("\\rfmod")) {
                LOGGER.debug("Command received: Restarting Radio Thread...");
                startRadioSequence();
                event.cancel(); // Hide the command from chat
            }
        } catch (Exception e) {
            LOGGER.error("Failed to handleSendMessageToChat", e);
        }
    }

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for ShoutcastStreamer");
        StormEventDispatcher.registerEventHandler(this);
    }
}
