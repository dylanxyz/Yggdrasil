import YAML

if !@isdefined(DEBUG)
    const DEBUG = true
end

function upload_pipeline(definition)
    @info "Uploading pipeline..."
    if DEBUG
        YAML.write(stderr, definition)
    else
        open(`buildkite-agent pipeline upload`, stdout, write=true) do io
            YAML.write(io, definition)
        end
    end
end

function annotate(annotation; context="default", style="info", append=true)
    @assert style in ("success", "info", "warning", "error")
    @info "Uploading annotation..."
    if DEBUG
        write(stderr, annotation, '\n')
    else
        append = append ? `--append` : ``
        cmd = `buildkite-agent annotate --style $(style) --context $(context) $(append)`
        open(cmd, stdout, write=true) do io
            write(io, annotation)
        end
    end
end

agent() = Dict(
    :queue => "juliaecosystem",
    :arch => "x86_64",
    :os => "linux",
    :sandbox_capable => "true"
)

plugins() = [
    "JuliaCI/julia#v1" => Dict(
        "persist_depot_dirs" => "packages,artifacts,compiled",
        "version" => "1.7"
    )
]

wait_step() = Dict(:wait => "~")
group_step(name, steps) = Dict(:group => name, :steps => steps)

function jll_init_step(NAME, PROJECT, BB_HASH, PROJ_HASH)
    script = raw"""
    # Fail on error
    set -e

    export JULIA_PROJECT="${BUILDKITE_BUILD_CHECKOUT_PATH}/.ci"

    cd ${PROJECT}
    echo "Generating meta.json..."
    julia --compile=min ./build_tarballs.jl --meta-json=${NAME}.meta.json
    echo "Initializing JLL package..."
    julia ${BUILDKITE_BUILD_CHECKOUT_PATH}/.ci/jll_init.jl ${NAME}.meta.json
    """

    Dict(
        :label => "jll_init -- $NAME",
        :agents => agent(),
        :plugins => plugins(),
        :timeout_in_minutes => 60,
        :concurrency => 1,
        :concurrency_group => "yggdrasil/jll_init",
        :commands => [script],
        :env => Dict(
            "NAME" => NAME,
            "PROJECT" => PROJECT,
            "BB_HASH" => BB_HASH,
            "PROJ_HASH" => PROJ_HASH
        )
    )
end

function build_step(NAME, PLATFORM, PROJECT, BB_HASH, PROJ_HASH)
    script = raw"""
    # Fail on error
    set -e

    export JULIA_PROJECT="${BUILDKITE_BUILD_CHECKOUT_PATH}/.ci"

    # Cleanup temporary things that might have been left-over
    ./clean_builds.sh
    ./clean_products.sh

    cd ${PROJECT}
    julia ./build_tarballs.jl --verbose ${PLATFORM}

    # # After building, we take the single tarball produced with the proper NAME, and upload it:
    # TARBALLS=( ./products/${NAME%@*}*${PLATFORM}*.tar.gz )
    # if [[ "${#TARBALLS[@]}" != 1 ]]; then
    #     echo "Multiple tarballs?  This isn't right!" >&2
    #     exit 1
    # fi
    # # Upload with curl
    # ACL="x-amz-acl:public-read"
    # CONTENT_TYPE="application/x-gtar"
    # BUCKET="julia-bb-buildcache"
    # BUCKET_PATH="${BB_HASH}/${PROJ_HASH}/${PLATFORM}.tar.gz"
    # DATE="$(date -R)"
    # S3SIGNATURE=\$(echo -en "PUT\n\n${CONTENT_TYPE}\n${DATE}\n${ACL}\n/${BUCKET}/${BUCKET_PATH}" | openssl sha1 -hmac "${S3SECRET}" -binary | base64)
    # HOST="${BUCKET}.s3.amazonaws.com"
    # echo "Uploading artifact to https://${HOST}/${BUCKET_PATH}"
    # curl -X PUT -T "${TARBALLS[0]}" \
    #     -H "Host: ${HOST}" \
    #     -H "Date: ${DATE}" \
    #     -H "Content-Type: ${CONTENT_TYPE}" \
    #     -H "${ACL}" \
    #     -H "Authorization: AWS ${S3KEY}:${S3SIGNATURE}" \
    #     "https://${HOST}/${BUCKET_PATH}"

    # if [[ "$?" != 0 ]]; then
    #     echo "Failed to upload artifact!" >&2
    #     exit 1
    # fi
    """

    Dict(
        :label => "build -- $NAME -- $PLATFORM",
        :agents => agent(),
        :plugins => plugins(),
        :timeout_in_minutes => 60,
        :priority => -1,
        :concurrency => 16,
        :concurrency_group => "yggdrasil/build/$NAME", # Could use ENV["BUILDKITE_JOB_ID"]
        :commands => [script],
        :env => Dict(
            "NAME" => NAME,
            "PLATFORM" => PLATFORM,
            "PROJECT" => PROJECT,
            "BB_HASH" => BB_HASH,
            "PROJ_HASH" => PROJ_HASH
        )
    )
end

function register_step(NAME, PROJECT, BB_HASH, PROJ_HASH)
    script = raw"""
    # Fail on error
    set -e

    export JULIA_PROJECT="${BUILDKITE_BUILD_CHECKOUT_PATH}/.ci"

    cd ${PROJECT}
    echo "Generating meta.json..."
    julia --compile=min ./build_tarballs.jl --meta-json=${NAME}.meta.json
    echo "Registering ${NAME}..."
    export BB_HASH PROJ_HASH
    julia ${BUILDKITE_BUILD_CHECKOUT_PATH}/.ci/register_package.jl ${NAME}.meta.json --verbose
    """

    Dict(
        :label => "register -- $NAME",
        :agents => agent(),
        :plugins => plugins(),
        :timeout_in_minutes => 60,
        :commands => [script],
        :env => Dict(
            "NAME" => NAME,
            "PROJECT" => PROJECT,
            "BB_HASH" => BB_HASH,
            "PROJ_HASH" => PROJ_HASH
        )
    )
end
