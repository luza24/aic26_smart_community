# generated from genmsg/cmake/pkg-genmsg.cmake.em

message(STATUS "servicelea: 0 messages, 1 services")

set(MSG_I_FLAGS "-Istd_msgs:/opt/ros/noetic/share/std_msgs/cmake/../msg")

# Find all generators
find_package(gencpp REQUIRED)
find_package(geneus REQUIRED)
find_package(genlisp REQUIRED)
find_package(gennodejs REQUIRED)
find_package(genpy REQUIRED)

add_custom_target(servicelea_generate_messages ALL)

# verify that message/service dependencies have not changed since configure



get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_custom_target(_servicelea_generate_messages_check_deps_${_filename}
  COMMAND ${CATKIN_ENV} ${PYTHON_EXECUTABLE} ${GENMSG_CHECK_DEPS_SCRIPT} "servicelea" "/root/catkin_ws/src/servicelea/srv/person.srv" ""
)

#
#  langs = gencpp;geneus;genlisp;gennodejs;genpy
#

### Section generating for lang: gencpp
### Generating Messages

### Generating Services
_generate_srv_cpp(servicelea
  "/root/catkin_ws/src/servicelea/srv/person.srv"
  "${MSG_I_FLAGS}"
  ""
  ${CATKIN_DEVEL_PREFIX}/${gencpp_INSTALL_DIR}/servicelea
)

### Generating Module File
_generate_module_cpp(servicelea
  ${CATKIN_DEVEL_PREFIX}/${gencpp_INSTALL_DIR}/servicelea
  "${ALL_GEN_OUTPUT_FILES_cpp}"
)

add_custom_target(servicelea_generate_messages_cpp
  DEPENDS ${ALL_GEN_OUTPUT_FILES_cpp}
)
add_dependencies(servicelea_generate_messages servicelea_generate_messages_cpp)

# add dependencies to all check dependencies targets
get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_dependencies(servicelea_generate_messages_cpp _servicelea_generate_messages_check_deps_${_filename})

# target for backward compatibility
add_custom_target(servicelea_gencpp)
add_dependencies(servicelea_gencpp servicelea_generate_messages_cpp)

# register target for catkin_package(EXPORTED_TARGETS)
list(APPEND ${PROJECT_NAME}_EXPORTED_TARGETS servicelea_generate_messages_cpp)

### Section generating for lang: geneus
### Generating Messages

### Generating Services
_generate_srv_eus(servicelea
  "/root/catkin_ws/src/servicelea/srv/person.srv"
  "${MSG_I_FLAGS}"
  ""
  ${CATKIN_DEVEL_PREFIX}/${geneus_INSTALL_DIR}/servicelea
)

### Generating Module File
_generate_module_eus(servicelea
  ${CATKIN_DEVEL_PREFIX}/${geneus_INSTALL_DIR}/servicelea
  "${ALL_GEN_OUTPUT_FILES_eus}"
)

add_custom_target(servicelea_generate_messages_eus
  DEPENDS ${ALL_GEN_OUTPUT_FILES_eus}
)
add_dependencies(servicelea_generate_messages servicelea_generate_messages_eus)

# add dependencies to all check dependencies targets
get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_dependencies(servicelea_generate_messages_eus _servicelea_generate_messages_check_deps_${_filename})

# target for backward compatibility
add_custom_target(servicelea_geneus)
add_dependencies(servicelea_geneus servicelea_generate_messages_eus)

# register target for catkin_package(EXPORTED_TARGETS)
list(APPEND ${PROJECT_NAME}_EXPORTED_TARGETS servicelea_generate_messages_eus)

### Section generating for lang: genlisp
### Generating Messages

### Generating Services
_generate_srv_lisp(servicelea
  "/root/catkin_ws/src/servicelea/srv/person.srv"
  "${MSG_I_FLAGS}"
  ""
  ${CATKIN_DEVEL_PREFIX}/${genlisp_INSTALL_DIR}/servicelea
)

### Generating Module File
_generate_module_lisp(servicelea
  ${CATKIN_DEVEL_PREFIX}/${genlisp_INSTALL_DIR}/servicelea
  "${ALL_GEN_OUTPUT_FILES_lisp}"
)

add_custom_target(servicelea_generate_messages_lisp
  DEPENDS ${ALL_GEN_OUTPUT_FILES_lisp}
)
add_dependencies(servicelea_generate_messages servicelea_generate_messages_lisp)

# add dependencies to all check dependencies targets
get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_dependencies(servicelea_generate_messages_lisp _servicelea_generate_messages_check_deps_${_filename})

# target for backward compatibility
add_custom_target(servicelea_genlisp)
add_dependencies(servicelea_genlisp servicelea_generate_messages_lisp)

# register target for catkin_package(EXPORTED_TARGETS)
list(APPEND ${PROJECT_NAME}_EXPORTED_TARGETS servicelea_generate_messages_lisp)

### Section generating for lang: gennodejs
### Generating Messages

### Generating Services
_generate_srv_nodejs(servicelea
  "/root/catkin_ws/src/servicelea/srv/person.srv"
  "${MSG_I_FLAGS}"
  ""
  ${CATKIN_DEVEL_PREFIX}/${gennodejs_INSTALL_DIR}/servicelea
)

### Generating Module File
_generate_module_nodejs(servicelea
  ${CATKIN_DEVEL_PREFIX}/${gennodejs_INSTALL_DIR}/servicelea
  "${ALL_GEN_OUTPUT_FILES_nodejs}"
)

add_custom_target(servicelea_generate_messages_nodejs
  DEPENDS ${ALL_GEN_OUTPUT_FILES_nodejs}
)
add_dependencies(servicelea_generate_messages servicelea_generate_messages_nodejs)

# add dependencies to all check dependencies targets
get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_dependencies(servicelea_generate_messages_nodejs _servicelea_generate_messages_check_deps_${_filename})

# target for backward compatibility
add_custom_target(servicelea_gennodejs)
add_dependencies(servicelea_gennodejs servicelea_generate_messages_nodejs)

# register target for catkin_package(EXPORTED_TARGETS)
list(APPEND ${PROJECT_NAME}_EXPORTED_TARGETS servicelea_generate_messages_nodejs)

### Section generating for lang: genpy
### Generating Messages

### Generating Services
_generate_srv_py(servicelea
  "/root/catkin_ws/src/servicelea/srv/person.srv"
  "${MSG_I_FLAGS}"
  ""
  ${CATKIN_DEVEL_PREFIX}/${genpy_INSTALL_DIR}/servicelea
)

### Generating Module File
_generate_module_py(servicelea
  ${CATKIN_DEVEL_PREFIX}/${genpy_INSTALL_DIR}/servicelea
  "${ALL_GEN_OUTPUT_FILES_py}"
)

add_custom_target(servicelea_generate_messages_py
  DEPENDS ${ALL_GEN_OUTPUT_FILES_py}
)
add_dependencies(servicelea_generate_messages servicelea_generate_messages_py)

# add dependencies to all check dependencies targets
get_filename_component(_filename "/root/catkin_ws/src/servicelea/srv/person.srv" NAME_WE)
add_dependencies(servicelea_generate_messages_py _servicelea_generate_messages_check_deps_${_filename})

# target for backward compatibility
add_custom_target(servicelea_genpy)
add_dependencies(servicelea_genpy servicelea_generate_messages_py)

# register target for catkin_package(EXPORTED_TARGETS)
list(APPEND ${PROJECT_NAME}_EXPORTED_TARGETS servicelea_generate_messages_py)



if(gencpp_INSTALL_DIR AND EXISTS ${CATKIN_DEVEL_PREFIX}/${gencpp_INSTALL_DIR}/servicelea)
  # install generated code
  install(
    DIRECTORY ${CATKIN_DEVEL_PREFIX}/${gencpp_INSTALL_DIR}/servicelea
    DESTINATION ${gencpp_INSTALL_DIR}
  )
endif()
if(TARGET std_msgs_generate_messages_cpp)
  add_dependencies(servicelea_generate_messages_cpp std_msgs_generate_messages_cpp)
endif()

if(geneus_INSTALL_DIR AND EXISTS ${CATKIN_DEVEL_PREFIX}/${geneus_INSTALL_DIR}/servicelea)
  # install generated code
  install(
    DIRECTORY ${CATKIN_DEVEL_PREFIX}/${geneus_INSTALL_DIR}/servicelea
    DESTINATION ${geneus_INSTALL_DIR}
  )
endif()
if(TARGET std_msgs_generate_messages_eus)
  add_dependencies(servicelea_generate_messages_eus std_msgs_generate_messages_eus)
endif()

if(genlisp_INSTALL_DIR AND EXISTS ${CATKIN_DEVEL_PREFIX}/${genlisp_INSTALL_DIR}/servicelea)
  # install generated code
  install(
    DIRECTORY ${CATKIN_DEVEL_PREFIX}/${genlisp_INSTALL_DIR}/servicelea
    DESTINATION ${genlisp_INSTALL_DIR}
  )
endif()
if(TARGET std_msgs_generate_messages_lisp)
  add_dependencies(servicelea_generate_messages_lisp std_msgs_generate_messages_lisp)
endif()

if(gennodejs_INSTALL_DIR AND EXISTS ${CATKIN_DEVEL_PREFIX}/${gennodejs_INSTALL_DIR}/servicelea)
  # install generated code
  install(
    DIRECTORY ${CATKIN_DEVEL_PREFIX}/${gennodejs_INSTALL_DIR}/servicelea
    DESTINATION ${gennodejs_INSTALL_DIR}
  )
endif()
if(TARGET std_msgs_generate_messages_nodejs)
  add_dependencies(servicelea_generate_messages_nodejs std_msgs_generate_messages_nodejs)
endif()

if(genpy_INSTALL_DIR AND EXISTS ${CATKIN_DEVEL_PREFIX}/${genpy_INSTALL_DIR}/servicelea)
  install(CODE "execute_process(COMMAND \"/usr/bin/python3\" -m compileall \"${CATKIN_DEVEL_PREFIX}/${genpy_INSTALL_DIR}/servicelea\")")
  # install generated code
  install(
    DIRECTORY ${CATKIN_DEVEL_PREFIX}/${genpy_INSTALL_DIR}/servicelea
    DESTINATION ${genpy_INSTALL_DIR}
  )
endif()
if(TARGET std_msgs_generate_messages_py)
  add_dependencies(servicelea_generate_messages_py std_msgs_generate_messages_py)
endif()
