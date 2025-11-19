odin build src/ -out:./bin/game
if [ "$1" = "-d" ]; then
    echo "Running in debug..."
    ./bin/game --debug
else
    echo "Running without debug.."
    ./bin/game
fi
