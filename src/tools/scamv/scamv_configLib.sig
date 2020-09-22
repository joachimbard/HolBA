signature scamv_configLib =
sig
    type scamv_config
    datatype arch_type = arm8
                       | m0

    datatype gen_type = gen_rand
                      | prefetch_strides
                      | qc
                      | slice
                      | from_file

    datatype obs_model = pc_trace
                       | mem_address_pc_trace
                       | cache_tag_index
                       | cache_tag_only
                       | cache_index_only
                       | cache_tag_index_part
                       | cache_tag_index_part_page
                       | cache_speculation

    datatype hw_obs_model = hw_time
                          | hw_cache_tag_index
                          | hw_cache_index_numvalid
                          | hw_cache_tag_index_part
                          | hw_cache_tag_index_part_page

    val default_cfg : scamv_config
    val print_scamv_opt_usage : unit -> unit
    val scamv_getopt_config : unit -> scamv_config
end
