/**
 * SCORM API wrapper for LMS communication.
 * Supports SCORM 1.2 (cmi.core) and SCORM 2004 (cmi.score.scaled, cmi.completion_status).
 * Закладка: cmi.core.lesson_location. Время: cmi.core.session_time (формат HHHH:MM:SS.ss).
 */
(function(global) {
  'use strict';

  var API = null;
  var sessionStartTime = 0;

  function findAPI(win) {
    if (!win) return null;
    if (win.API) return win.API;
    if (win.API_1484_11) return win.API_1484_11;
    for (var i = 0; i < win.frames.length; i++) {
      var candidate = findAPI(win.frames[i]);
      if (candidate) return candidate;
    }
    return null;
  }

  /** Формат времени SCORM: HHHH:MM:SS.ss (CMITimespan) */
  function formatSessionTime(seconds) {
    var s = Math.floor(seconds);
    var h = Math.floor(s / 3600);
    s -= h * 3600;
    var m = Math.floor(s / 60);
    s -= m * 60;
    var frac = Math.min(99, Math.round((seconds % 1) * 100));
    function pad(n, len) {
      var str = String(n);
      while (str.length < len) str = '0' + str;
      return str;
    }
    return pad(h, 4) + ':' + pad(m, 2) + ':' + pad(s, 2) + '.' + pad(frac, 2);
  }

  var SCORM_API = {
    initialized: false,
    _finished: false,
    version: '1.2',

    initialize: function() {
      API = findAPI(window);
      if (!API) {
        API = findAPI(window.parent);
      }
      if (!API) {
        API = findAPI(window.top);
      }
      if (!API) {
        try {
          if (window.parent && window.parent !== window) {
            API = findAPI(window.parent);
          }
        } catch (e) {}
      }
      if (API) {
        try {
          var result = API.LMSInitialize('');
          this.initialized = (result && result.toString() === 'true') || result === true;
          if (this.initialized) sessionStartTime = Date.now();
        } catch (e) {
          this.initialized = false;
        }
      }
      return this.initialized;
    },

    /** Читает закладку из LMS (номер слайда или строка). */
    getLessonLocation: function() {
      if (!this.initialized || !API) return '';
      try {
        var v = API.LMSGetValue('cmi.core.lesson_location');
        return (v !== undefined && v !== null) ? String(v).trim() : '';
      } catch (e) {
        return '';
      }
    },

    /** Сохраняет закладку (номер слайда). */
    setLessonLocation: function(location) {
      if (!this.initialized || !API) return false;
      try {
        API.LMSSetValue('cmi.core.lesson_location', String(location));
        return true;
      } catch (e) {
        return false;
      }
    },

    /** Читает cmi.suspend_data (строка для произвольных данных). */
    getSuspendData: function() {
      if (!this.initialized || !API) return '';
      try {
        var v = API.LMSGetValue('cmi.suspend_data');
        return (v !== undefined && v !== null) ? String(v) : '';
      } catch (e) {
        return '';
      }
    },

    /** Записывает cmi.suspend_data. Commit выполняет вызывающий код. */
    setSuspendData: function(value) {
      if (!this.initialized || !API) return false;
      try {
        API.LMSSetValue('cmi.suspend_data', String(value));
        return true;
      } catch (e) {
        return false;
      }
    },

    /** Читает имя обучающегося из LMS (хранится в suspend_data как JSON). */
    getLearnerName: function() {
      var raw = this.getSuspendData();
      if (!raw || !raw.trim()) return '';
      try {
        var obj = JSON.parse(raw);
        return (obj && typeof obj.userName === 'string') ? obj.userName.trim() : '';
      } catch (e) {
        return '';
      }
    },

    /** Сохраняет имя обучающегося в LMS (в suspend_data), затем commit. */
    setLearnerName: function(name) {
      if (!this.initialized || !API) return false;
      try {
        var raw = this.getSuspendData();
        var obj = {};
        try {
          if (raw && raw.trim()) obj = JSON.parse(raw);
        } catch (e) {}
        obj.userName = (name !== undefined && name !== null) ? String(name).trim() : '';
        this.setSuspendData(JSON.stringify(obj));
        API.LMSCommit('');
        return true;
      } catch (e) {
        return false;
      }
    },

    /** Записывает в LMS время текущей сессии и выполняет commit. */
    setSessionTimeAndCommit: function() {
      if (!this.initialized || !API || sessionStartTime <= 0) return false;
      try {
        var elapsedSec = (Date.now() - sessionStartTime) / 1000;
        API.LMSSetValue('cmi.core.session_time', formatSessionTime(elapsedSec));
        API.LMSCommit('');
        return true;
      } catch (e) {
        return false;
      }
    },

    /** Сохраняет закладку, время сессии, имя (если передано) и выполняет commit (при смене слайда / перед выходом). */
    commitProgress: function(lessonLocation, learnerName) {
      if (!this.initialized || !API) return false;
      try {
        if (lessonLocation !== undefined && lessonLocation !== null) {
          API.LMSSetValue('cmi.core.lesson_location', String(lessonLocation));
        }
        if (sessionStartTime > 0) {
          var elapsedSec = (Date.now() - sessionStartTime) / 1000;
          API.LMSSetValue('cmi.core.session_time', formatSessionTime(elapsedSec));
        }
        if (learnerName !== undefined && learnerName !== null) {
          var raw = this.getSuspendData();
          var obj = {};
          try {
            if (raw && raw.trim()) obj = JSON.parse(raw);
          } catch (e) {}
          obj.userName = String(learnerName).trim();
          this.setSuspendData(JSON.stringify(obj));
        }
        API.LMSCommit('');
        return true;
      } catch (e) {
        return false;
      }
    },

    setScore: function(scorePercent) {
      if (!this.initialized || !API) return false;
      try {
        API.LMSSetValue('cmi.core.score.raw', Math.round(scorePercent));
        API.LMSSetValue('cmi.core.score.min', '0');
        API.LMSSetValue('cmi.core.score.max', '100');
        API.LMSSetValue('cmi.core.lesson_status', scorePercent >= 70 ? 'passed' : 'completed');
        API.LMSCommit('');
        return true;
      } catch (e) {
        return false;
      }
    },

    setCompleted: function() {
      if (!API) return false;
      try {
        API.LMSSetValue('cmi.core.lesson_status', 'completed');
        API.LMSCommit('');
        return true;
      } catch (e) {
        return false;
      }
    },

    /** Корректное завершение: закладка + время + имя (если передано) + статус + LMSFinish(''). Повторный вызов безопасен (no-op). */
    finish: function(lessonLocation, learnerName) {
      if (!API) return false;
      if (this._finished) return true;
      try {
        if (lessonLocation !== undefined && lessonLocation !== null) {
          API.LMSSetValue('cmi.core.lesson_location', String(lessonLocation));
        }
        if (sessionStartTime > 0) {
          var elapsedSec = (Date.now() - sessionStartTime) / 1000;
          API.LMSSetValue('cmi.core.session_time', formatSessionTime(elapsedSec));
        }
        if (learnerName !== undefined && learnerName !== null) {
          var raw = this.getSuspendData();
          var obj = {};
          try {
            if (raw && raw.trim()) obj = JSON.parse(raw);
          } catch (e) {}
          obj.userName = String(learnerName).trim();
          this.setSuspendData(JSON.stringify(obj));
        }
        this.setCompleted();
        API.LMSFinish('');
        this._finished = true;
        return true;
      } catch (e) {
        return false;
      }
    }
  };

  global.SCORM_API = SCORM_API;
})(typeof window !== 'undefined' ? window : this);
