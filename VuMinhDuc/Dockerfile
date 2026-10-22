# Runtime Stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8687

# SDK Build & Publish Stage (Tối ưu: Bỏ bước build thừa, chỉ publish 1 lần duy nhất)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["VuMinhDuc.csproj", "./"]
RUN dotnet restore "./VuMinhDuc.csproj"
COPY . .
RUN dotnet publish "./VuMinhDuc.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false --no-restore

# Final Runtime Image
FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "VuMinhDuc.dll"]
