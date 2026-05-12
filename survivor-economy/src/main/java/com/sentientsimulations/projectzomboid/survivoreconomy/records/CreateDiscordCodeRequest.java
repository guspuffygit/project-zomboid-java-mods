package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import com.fasterxml.jackson.annotation.JsonProperty;
import org.jspecify.annotations.Nullable;

/** Request body for {@code POST /economy/discord/link/code/discord}. */
public record CreateDiscordCodeRequest(
        @JsonProperty(required = true) String discordId, @Nullable String discordUsername) {}
